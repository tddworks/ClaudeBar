#if os(macOS)
import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An app that serves its usage on this Mac: found by its process, asked with
/// what it was started with, on the ports it listens on — loopback only.
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

    private func fetch(pgrep: String, lsof: String = "acme 42 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:5001 (LISTEN)\nacme 42 me 11u IPv4 0x1 0t0 TCP 127.0.0.1:5002 (LISTEN)",
                       answering: Set<String> = ["https://127.0.0.1:5002/status"], seen: Seen = Seen()) async throws -> Response {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(callJSON.utf8))
        let commands = MockCLIExecutor()
        given(commands).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, args, _, _, _, _ in
                // The app's ports, only when asked about the app's own PID.
                return CLIResult(output: binary.hasSuffix("pgrep") ? pgrep : args.last == "42" ? lsof : "")
            }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            let url = request.url!.absoluteString
            seen.urls.append(url)
            seen.csrf.append(request.value(forHTTPHeaderField: "X-Csrf"))
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: answering.contains(url) ? 200 : 404, httpVersion: nil, headerFields: nil)!)
        }
        return try await Platform.macLocalServer(call, commands, network, { [] }).fetch(with: nil)
    }

    @Test func `should ask the running app on each port it listens on, with the token it was started with, until one answers`() async throws {
        let seen = Seen()
        let response = try await fetch(pgrep: "42 /opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080", seen: seen)
        #expect(response.status == 200)
        #expect(seen.urls == ["https://127.0.0.1:5001/usage", "https://127.0.0.1:5001/status", "https://127.0.0.1:5002/usage", "https://127.0.0.1:5002/status"])
        #expect(seen.csrf.allSatisfy { $0 == "tok-1" })
    }

    @Test func `should ask the plain HTTP port the app was started with last`() async throws {
        let seen = Seen()
        _ = try await fetch(pgrep: "42 /opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080",
                            answering: ["http://127.0.0.1:8080/usage"], seen: seen)
        #expect(seen.urls.last == "http://127.0.0.1:8080/usage")
    }

    @Test func `should treat the app as not running when only another app's process shares its name`() async throws {
        await #expect(throws: CLIMissingError.self) {
            try await fetch(pgrep: "77 /Applications/Other.app/acme_server --csrf x")
        }
    }

    @Test func `should treat the app as not running when no process is found`() async throws {
        await #expect(throws: CLIMissingError.self) { try await fetch(pgrep: "") }
    }

    @Test func `should ask to sign in when the app runs without its token`() async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await fetch(pgrep: "42 /opt/acme/acme_server --app acme")
        }
    }

    @Test func `should ask the running app with its token while a CLI of the same name runs beside it without one`() async throws {
        let seen = Seen()
        let response = try await fetch(pgrep: "7 /opt/acme/acme_server --app acme\n42 /opt/acme/acme_server --app acme --csrf tok-2", seen: seen)
        #expect(response.status == 200)
        #expect(seen.urls.last == "https://127.0.0.1:5002/status")
        #expect(seen.csrf.allSatisfy { $0 == "tok-2" })
    }

    @Test func `should say it couldn't connect to the app when no port answers`() async throws {
        await #expect(throws: UsageError.executionFailed("Could not connect to Acme")) {
            try await fetch(pgrep: "42 /opt/acme/acme_server --app acme --csrf t", answering: [])
        }
    }

    @Test func `should be ready only while the app itself is running, without starting a process to check`() throws {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(#"{"app":"Acme","process":{"names":["acme_server"],"match":["/acme/"]},"paths":["/u"]}"#.utf8))
        let running = Platform.macLocalServer(call, MockCLIExecutor(), MockNetworkClient(), { ["/opt/acme/acme_server"] })
        let other = Platform.macLocalServer(call, MockCLIExecutor(), MockNetworkClient(), { ["/Applications/Other.app/acme_server"] })
        #expect(running.isReady())
        #expect(!other.isReady())
    }

}
#endif
