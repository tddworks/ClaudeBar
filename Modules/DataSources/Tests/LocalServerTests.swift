import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An app that serves its usage on this machine: found by its process, asked
/// with what it was started with, on the ports it listens on, loopback only.
@Suite
struct LocalServerTests {
    private let callJSON = #"""
    {"app":"Acme","process":{"names":["acme_server"],"match":["--app acme"]},
     "values":{"csrf":"--csrf[=\\s]+(\\S+)","httpPort":"--http_port[=\\s]+(\\d+)"},
     "required":["csrf"],
     "paths":["/usage","/status"],
     "plainHTTPPort":"httpPort",
     "headers":{"X-Csrf":"{{csrf}}"},
     "body":"{}"}
    """#

    final class Seen: @unchecked Sendable { var urls: [String] = []; var csrf: [String?] = [] }

    private func server(_ commandLine: String?, ports: [Int] = [5001, 5002],
                        answering: Set<String> = ["https://127.0.0.1:5002/status"], seen: Seen = Seen()) throws -> LocalServerFetcher {
        let running = commandLine.map { [RunningProgram(pid: 42, path: "/opt/acme/acme_server", commandLine: $0, ports: ports)] } ?? []
        return try server(running, answering: answering, seen: seen)
    }

    private func server(_ running: [RunningProgram],
                        answering: Set<String> = ["https://127.0.0.1:5002/status"], seen: Seen = Seen()) throws -> LocalServerFetcher {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(callJSON.utf8))
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            let url = request.url!.absoluteString
            seen.urls.append(url)
            seen.csrf.append(request.value(forHTTPHeaderField: "X-Csrf"))
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: answering.contains(url) ? 200 : 404, httpVersion: nil, headerFields: nil)!)
        }
        return LocalServers(handing: running, network: network).fetcher(for: call)
    }

    @Test func `should ask the running app on each port it listens on, with the token it was started with, until one answers`() async throws {
        let seen = Seen()
        let response = try await server("/opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080", seen: seen).fetch(with: nil)
        #expect(response.status == 200)
        #expect(seen.urls == ["https://127.0.0.1:5001/usage", "https://127.0.0.1:5001/status", "https://127.0.0.1:5002/usage", "https://127.0.0.1:5002/status"])
        #expect(seen.csrf.allSatisfy { $0 == "tok-1" })
    }

    @Test func `should ask the plain HTTP port the app was started with last`() async throws {
        let seen = Seen()
        _ = try await server("/opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080",
                             answering: ["http://127.0.0.1:8080/usage"], seen: seen).fetch(with: nil)
        #expect(seen.urls.last == "http://127.0.0.1:8080/usage")
    }

    @Test func `should treat the app as not running when only another app's process shares its name`() async throws {
        await #expect(throws: CLIMissingError.self) {
            try await server("/Applications/Other.app/acme_server --csrf x").fetch(with: nil)
        }
    }

    @Test func `should treat the app as not running when no process is found`() async throws {
        await #expect(throws: CLIMissingError.self) { try await server(nil).fetch(with: nil) }
    }

    @Test func `should ask to sign in when the app runs without its token`() async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await server("/opt/acme/acme_server --app acme").fetch(with: nil)
        }
    }

    @Test func `should ask the running app with its token while a CLI of the same name runs beside it without one`() async throws {
        let seen = Seen()
        // Listed out of PID order, as an OS may list them; only the app listens.
        let response = try await server([
            RunningProgram(pid: 42, path: "/opt/acme/acme_server", commandLine: "/opt/acme/acme_server --app acme --csrf tok-2", ports: [5001, 5002]),
            RunningProgram(pid: 7, path: "/opt/acme/acme_server", commandLine: "/opt/acme/acme_server --app acme", ports: []),
        ], seen: seen).fetch(with: nil)
        #expect(response.status == 200)
        #expect(seen.urls.last == "https://127.0.0.1:5002/status")
        #expect(seen.csrf.allSatisfy { $0 == "tok-2" })
    }

    @Test func `should say it couldn't connect to the app when no port answers`() async throws {
        await #expect(throws: UsageError.executionFailed("Could not connect to Acme")) {
            try await server("/opt/acme/acme_server --app acme --csrf t", answering: []).fetch(with: nil)
        }
    }

    @Test func `should say the app listens on no port when it has none and no plain HTTP port`() async throws {
        await #expect(throws: UsageError.executionFailed("Acme isn't listening on any port")) {
            try await server("/opt/acme/acme_server --app acme --csrf t", ports: []).fetch(with: nil)
        }
    }

    @Test func `should be ready only while the app itself is running, without reading a command line`() throws {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(#"{"app":"Acme","process":{"names":["acme_server"],"match":["/acme/"]},"paths":["/u"]}"#.utf8))
        func servers(_ path: String) -> LocalServers {
            let running = MockRunningPrograms()
            given(running).paths().willReturn([path])
            return LocalServers(running: running, commandLines: MockProgramCommandLines(), ports: MockListeningPorts(),
                                network: MockNetworkClient())
        }
        #expect(servers("/opt/acme/acme_server").fetcher(for: call).isReady())
        #expect(!servers("/Applications/Other.app/acme_server").fetcher(for: call).isReady())
    }
}
