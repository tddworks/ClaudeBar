import Foundation
import Testing
@testable import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The `LocalNetwork` port's contract (MODULAR_DESIGN §10), run against this
/// platform's adapter: it finds the program this test runs in by its path,
/// its command line and a port it listens on, and asks a server on
/// 127.0.0.1, over plain HTTP and over TLS with a certificate made for
/// another name. Linux has no adapter yet (MODULAR_DESIGN §10, phase 6), so
/// it is skipped there, saying why.
@Suite(.serialized, .enabled(if: Platform.current.localServers != nil,
                             "asks a local server: \(Platform.current.name) has no LocalNetwork adapter yet"))
struct LocalNetworkContract {
    private static let own = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    private static let pid = Int(ProcessInfo.processInfo.processIdentifier)

    private func servers() throws -> LocalServers {
        try #require(Platform.current.localServers, "\(Platform.current.name) has no LocalNetwork adapter")
    }

    @Test func `should list the program this test runs in among those running`() throws {
        let names = try servers().running.paths().map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
        #expect(names.contains(Self.own.lastPathComponent.lowercased()))
    }

    @Test func `should read this test's own command line, with its pid, among those that name its program`() async throws {
        let name = Self.own.deletingPathExtension().lastPathComponent
        let lines = try await servers().commandLines.commandLines(naming: [name])
        let mine = try #require(lines.first { $0.pid == Self.pid }, "\(lines.count) lines name \(name), none with pid \(Self.pid)")
        #expect(mine.text.lowercased().contains(name.lowercased()))
    }

    @Test func `should list a port this test listens on among its listening ports`() async throws {
        let server = try LoopbackServer(answers: [])
        defer { server.close() }
        #expect(try await servers().ports.ports(of: Self.pid).contains(server.port))
    }

    @Test func `should ask a plain HTTP server with the method, headers and body given, and answer what it said`() async throws {
        let server = try LoopbackServer(answers: [
            "HTTP/1.1 201 Created\r\nX-Answer: yes\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello",
        ])
        defer { server.close() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/rpc/Get?x=1")!)
        request.httpMethod = "POST"
        request.setValue("tok-1", forHTTPHeaderField: "X-Csrf")
        request.httpBody = Data(#"{"q":1}"#.utf8)
        request.timeoutInterval = 10

        let (data, response) = try await servers().network.request(request)

        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 201)
        #expect(http.value(forHTTPHeaderField: "X-Answer") == "yes")
        #expect(String(decoding: data, as: UTF8.self) == "hello")
        let asked = try #require(server.requests.first)
        #expect(asked.hasPrefix("POST /rpc/Get?x=1 HTTP/1.1\r\n"))
        #expect(asked.lowercased().contains("\r\nx-csrf: tok-1\r\n"))
        #expect(asked.hasSuffix("\r\n\r\n{\"q\":1}"))
    }

    @Test func `should hand back a redirect to another server without following it`() async throws {
        let elsewhere = try LoopbackServer(answers: ["HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"])
        defer { elsewhere.close() }
        let server = try LoopbackServer(answers: [
            "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:\(elsewhere.port)/other\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        ])
        defer { server.close() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/usage")!)
        request.timeoutInterval = 10

        let (_, response) = try await servers().network.request(request)

        #expect((response as? HTTPURLResponse)?.statusCode == 302)
        #expect(elsewhere.requests.isEmpty)
    }

    @Test func `should ask a TLS server whose certificate is self-signed for another name`() async throws {
        let openssl = try #require(Self.openssl(), "no openssl to serve TLS with")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loopback-tls-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = folder.appendingPathComponent("key.pem").path, certificate = folder.appendingPathComponent("cert.pem").path
        // openssl runs as the app runs a program, never through
        // `Foundation.Process`: on Windows that hands every child the files the
        // test process has open, failing `ProcessesContract` running beside it (#586).
        let processes = try #require(Platform.current.processes)
        let made = try await SubprocessSupport.run(
            executablePath: openssl,
            arguments: ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", certificate,
                        "-days", "1", "-subj", "/CN=not-localhost"]
        )
        try #require(made.exitCode == 0, "openssl couldn't make a certificate")

        let port = try LoopbackServer.freePort()
        #if os(Windows)
        let accept = "127.0.0.1:\(port)"
        #else
        let accept = "\(port)"
        #endif
        let server = try processes.conversation(
            openssl, ["s_server", "-accept", accept, "-cert", certificate, "-key", key, "-www", "-quiet"], nil, nil
        )
        defer { server.close() }
        var request = URLRequest(url: URL(string: "https://127.0.0.1:\(port)/")!)
        request.timeoutInterval = 5

        // The server takes a moment to start listening.
        let clock = ContinuousClock(), deadline = clock.now + .seconds(20)
        var answer: (Data, URLResponse)?
        var failure: (any Error)?
        while answer == nil, clock.now < deadline {
            do {
                answer = try await servers().network.request(request)
            } catch {
                failure = error
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        let (data, response) = try #require(answer, "never answered: \(String(describing: failure))")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("s_server"))
    }

    /// The Mac's own openssl, or Git for Windows'.
    private static func openssl() -> String? {
        #if os(Windows)
        let candidates = [#"C:\Program Files\Git\usr\bin\openssl.exe"#, #"C:\Program Files\Git\mingw64\bin\openssl.exe"#]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? Platform.current.processes?.installed.find("openssl")
        #else
        return FileManager.default.isExecutableFile(atPath: "/usr/bin/openssl") ? "/usr/bin/openssl" : nil
        #endif
    }
}
