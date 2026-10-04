import Foundation
import Mockable
import Quotas
import Testing
@testable import DataSources

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

    final class Seen: @unchecked Sendable { var urls: [String] = []; var csrf: [String?] = []; var commands: [[String]] = [] }

    private func fetch(pgrep: String, lsof: String = "acme 42 me 10u IPv4 0x1 0t0 TCP 127.0.0.1:5001 (LISTEN)\nacme 42 me 11u IPv4 0x1 0t0 TCP 127.0.0.1:5002 (LISTEN)",
                       answering: Set<String> = ["https://127.0.0.1:5002/status"], seen: Seen = Seen()) async throws -> Response {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(callJSON.utf8))
        let commands = MockCLIExecutor()
        given(commands).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, args, _, _, _, _ in
                seen.commands.append([binary] + args)
                return CLIResult(output: binary.hasSuffix("pgrep") ? pgrep : lsof)
            }
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            let url = request.url!.absoluteString
            seen.urls.append(url)
            seen.csrf.append(request.value(forHTTPHeaderField: "X-Csrf"))
            return (Data(#"{"ok":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: answering.contains(url) ? 200 : 404, httpVersion: nil, headerFields: nil)!)
        }
        return try await LocalServerFetcher(call: call, commands: commands, network: network, processPaths: { [] }).fetch(with: nil)
    }

    @Test func `the running app is asked on each listening port until one answers`() async throws {
        let seen = Seen()
        let response = try await fetch(pgrep: "42 /opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080", seen: seen)
        #expect(response.status == 200)
        #expect(seen.urls == ["https://127.0.0.1:5001/usage", "https://127.0.0.1:5001/status", "https://127.0.0.1:5002/usage", "https://127.0.0.1:5002/status"])
        #expect(seen.csrf.allSatisfy { $0 == "tok-1" })
        #expect(seen.commands.first == ["/usr/bin/pgrep", "-lf", "acme_server"])
        #expect(seen.commands.last == ["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "42"])
    }

    @Test func `the plain HTTP port it was started with is asked last`() async throws {
        let seen = Seen()
        _ = try await fetch(pgrep: "42 /opt/acme/acme_server --app acme --csrf tok-1 --http_port 8080",
                            answering: ["http://127.0.0.1:8080/usage"], seen: seen)
        #expect(seen.urls.last == "http://127.0.0.1:8080/usage")
    }

    @Test func `another app's process with the same name is not it`() async throws {
        await #expect(throws: CLIMissingError.self) {
            try await fetch(pgrep: "77 /Applications/Other.app/acme_server --csrf x")
        }
    }

    @Test func `no process at all is the app not running`() async throws {
        await #expect(throws: CLIMissingError.self) { try await fetch(pgrep: "") }
    }

    @Test func `running without its token needs signing in`() async throws {
        await #expect(throws: UsageError.authenticationRequired) {
            try await fetch(pgrep: "42 /opt/acme/acme_server --app acme")
        }
    }

    @Test func `no port answering is a failure, not a guess`() async throws {
        await #expect(throws: UsageError.executionFailed("Could not connect to Acme")) {
            try await fetch(pgrep: "42 /opt/acme/acme_server --app acme --csrf t", answering: [])
        }
    }

    @Test func `readiness reads running executables without starting a process`() throws {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(#"{"app":"Acme","process":{"names":["acme_server"],"match":["/acme/"]},"paths":["/u"]}"#.utf8))
        let running = LocalServerFetcher(call: call, commands: MockCLIExecutor(), network: MockNetworkClient(), processPaths: { ["/opt/acme/acme_server"] })
        let other = LocalServerFetcher(call: call, commands: MockCLIExecutor(), network: MockNetworkClient(), processPaths: { ["/Applications/Other.app/acme_server"] })
        #expect(running.isReady())
        #expect(!other.isReady())
    }

    @Test func `it round-trips, and Import lists what it runs and where it asks`() throws {
        let call = try JSONDecoder().decode(LocalServerCall.self, from: Data(callJSON.utf8))
        #expect(try JSONDecoder().decode(LocalServerCall.self, from: JSONEncoder().encode(call)) == call)
        let fetch = Fetch.localServer(call)
        #expect(try JSONDecoder().decode(Fetch.self, from: JSONEncoder().encode(fetch)) == fetch)
        #expect(fetch.connection.urls == ["https://127.0.0.1:{{port}}/usage", "https://127.0.0.1:{{port}}/status"])
        #expect(fetch.connection.commands.first == ["/usr/bin/pgrep", "-lf", "acme_server"])
    }
}
