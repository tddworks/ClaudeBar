import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

@Suite
struct DataSourceTests {

    private func make(_ definition: DataSourceDefinition, network: any NetworkClient = MockNetworkClient(), environment: [String: String] = [:]) -> DataSource {
        DataSources.make(
            definition,
            providerId: "test",
            cliExecutor: MockCLIExecutor(),
            network: network,
            makeTransport: { _, _, _, _ in MockRPCTransport() },
            environment: { environment[$0] },
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func http(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> MockNetworkClient {
        let network = MockNetworkClient()
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        given(network).request(.any).willReturn((Data(body.utf8), response))
        return network
    }

    private func decode(_ json: String) throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data(json.utf8))
    }

    // MARK: - Definitions as JSON

    @Test
    func `should read a definition's key, fetch and mapping by their names, shown and with no fallback by default`() throws {
        let definition = try decode("""
        {"kind":"api","credential":{"environment":"KEY"},
         "fetch":{"http":{"url":"https://example.com/usage"}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """)

        #expect(definition.credential == .environment("KEY"))
        #expect(definition.fetch == .http(HTTPRequest(url: "https://example.com/usage")))
        #expect(definition.hidden == false)
        #expect(definition.fallback == nil)
    }

    @Test
    func `should reject a definition whose fetch names two ways at once`() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"x","fetch":{"http":{"url":"u"},"cli":{"cli":"c"}},"mapping":{"json":{"quotas":[]}}}"#)
        }
    }

    // MARK: - Fetching usage

    @Test
    func `should show the quota when the environment's API key is sent where the definition places it`() async throws {
        let network = MockNetworkClient()
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        given(network).request(.matching { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1" })
            .willReturn((Data(#"{"used":25}"#.utf8), response))
        let source = make(try decode("""
        {"kind":"api","credential":{"environment":"KEY"},
         "fetch":{"http":{"url":"https://example.com","headers":{"Authorization":"Bearer {{token}}"}}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"used"}]}}}
        """), network: network, environment: ["KEY": "sk-1"])

        let usage = try await source.fetchUsage()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 75)
    }

    @Test
    func `should show the raw status, headers and body when the connection is tested`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"nowhere"}]}}}
        """), network: http(#"{"data":{"limit":50}}"#, headers: ["X-Thing": "1"]))

        let response = try await source.fetchResponse()

        #expect(response.status == 200)
        #expect(response.header("x-thing") == "1")
        #expect(response.text == #"{"data":{"limit":50}}"#)
    }

    @Test
    func `should not be ready, and fail at finding the key, when there is no key`() async throws {
        let source = make(try decode("""
        {"kind":"api","credential":{"environment":"KEY"},"fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[]}}}
        """))

        #expect(await source.isReady() == false)
        await #expect(throws: DataSourceError(.lookup, .authenticationRequired)) { try await source.fetchUsage() }
    }

    @Test
    func `should fail at fetching, naming the HTTP status, when the server errors`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), network: http("", status: 500))

        await #expect(throws: DataSourceError(.fetch, .executionFailed("HTTP error: 500"))) { try await source.fetchUsage() }
    }

    @Test
    func `should say when to try again when the server is rate limited`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), network: http("", status: 429, headers: ["Retry-After": "120"]))

        await #expect(throws: DataSourceError(.fetch, .rateLimited(retryAt: Date(timeIntervalSince1970: 1_700_000_120)))) {
            try await source.fetchUsage()
        }
    }

    @Test
    func `should fail at reading the answer when the server doesn't answer in JSON`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), network: http("<html>"))

        await #expect(throws: DataSourceError(.mapping, .parseFailed("Response is not JSON"))) { try await source.fetchUsage() }
    }

    // MARK: - Mapping

    @Test
    func `should show a credit balance as money left with a budget and no reset`() throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"model","name":"Credits","at":"$.data","leftPercent":"left"}],
                            "cost":{"used":"$.data.usage","limit":"$.data.limit"}}}}
        """))

        let usage = try source.read(Response(text: #"{"data":{"left":24.8,"usage":37.6,"limit":50}}"#))

        #expect(usage.quota(for: .modelSpecific("Credits"))?.percentRemaining == 24.8)
        #expect(usage.quota(for: .modelSpecific("Credits"))?.resetsAt == nil)
        #expect(usage.costUsage?.budget == 50)
    }

    @Test
    func `should name each repeated quota from the answer, tidied, and skip one with no name`() throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"time","each":"$.limits",
           "name":{"firstOf":["name"],"dropPrefixes":[{"prefix":"codex_","capitalize":true}]},
           "usedPercent":"used"}]}}}
        """))

        let usage = try source.read(Response(text: #"{"limits":[{"name":"codex_spark","used":40},{"name":"","used":1}]}"#))

        #expect(usage.quotas.map(\.quotaType) == [.timeLimit("Spark")])
        #expect(usage.quotas.first?.percentRemaining == 60)
    }

    @Test
    func `should show when a quota resets as a countdown when the answer gives seconds from now`() throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"session","usedPercent":"used","resetsAt":{"secondsFromNow":"in"}}]}}}
        """))

        let quota = try source.read(Response(text: #"{"used":10,"in":5400}"#)).quota(for: .session)

        #expect(quota?.resetsAt == Date(timeIntervalSince1970: 1_700_005_400))
        #expect(quota?.resetText == "Resets in 1h 30m")
    }

    @Test
    func `should ask to sign in when the CLI screen says to log in, even beside its numbers`() throws {
        let source = make(try decode("""
        {"kind":"cli","fetch":{"cli":{"cli":"tool"}},
         "mapping":{"text":{"errors":[{"contains":["please log in"],"error":"authenticationRequired"}],
                            "quotas":[{"kind":"session","label":"5h limit","leftPercent":"([0-9]+)% left"}]}}}
        """))

        #expect(throws: DataSourceError(.mapping, .authenticationRequired)) {
            try source.read(Response(text: "5h limit 80% left\nPlease log in"))
        }
    }

    // MARK: - Where a CLI runs

    @Test
    func `should start a JSON-RPC CLI in ClaudeBar's own trusted folder (#267)`() async throws {
        // Codex 0.150+ trust-checks the directory it starts in (#267), so the
        // app-server must start in ClaudeBar's own probe directory.
        let started = StartedProcess()
        let transport = MockRPCTransport()
        given(transport).send(.any).willReturn(())
        given(transport).close().willReturn(())
        given(transport).receive().willReturn(Data(#"{"id":1,"result":{}}"#.utf8))
        let definition = try decode("""
        {"kind":"rpc","fetch":{"jsonRpc":{"cli":"codex","args":["app-server"],"workingDirectory":"dedicated","call":"read"}},
         "mapping":{"json":{"quotas":[]}}}
        """)
        let source = DataSources.make(
            definition,
            providerId: "test",
            cliExecutor: MockCLIExecutor(),
            network: MockNetworkClient(),
            makeTransport: { executable, arguments, _, directory in
                started.record(executable, arguments, directory)
                return transport
            },
            environment: { _ in nil },
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { Date() }
        )

        _ = try await source.fetchResponse()

        #expect(started.executable == "codex")
        #expect(started.arguments == ["app-server"])
        #expect(started.directory == CLIWorkingDirectory.resolve())
    }

    @Test
    func `should give up on a JSON-RPC CLI that stops answering, so the refresh ends (#517)`() async throws {
        // `codex app-server` can stall without answering or exiting; the
        // refresh must end with a timeout instead of syncing forever.
        let definition = try decode("""
        {"kind":"rpc","fetch":{"jsonRpc":{"cli":"codex","args":["app-server"],"call":"read","timeout":0.2}},
         "mapping":{"json":{"quotas":[]}}}
        """)
        let source = DataSources.make(
            definition,
            providerId: "test",
            cliExecutor: MockCLIExecutor(),
            network: MockNetworkClient(),
            makeTransport: { _, _, _, _ in SilentRPCTransport() },
            environment: { _ in nil },
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { Date() }
        )

        await #expect(throws: DataSourceError(.fetch, .timeout)) { try await source.fetchUsage() }
    }

    @Test
    func `should stop waiting on a silent JSON-RPC CLI when its refresh is cancelled, as removing the account does`() async throws {
        let definition = try decode("""
        {"kind":"rpc","fetch":{"jsonRpc":{"cli":"codex","args":["app-server"],"call":"read","timeout":60}},
         "mapping":{"json":{"quotas":[]}}}
        """)
        let source = DataSources.make(
            definition,
            providerId: "test",
            cliExecutor: MockCLIExecutor(),
            network: MockNetworkClient(),
            makeTransport: { _, _, _, _ in SilentRPCTransport() },
            environment: { _ in nil },
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { Date() }
        )
        let refresh = Task { try await source.fetchUsage() }
        try await Task.sleep(for: .milliseconds(100))

        refresh.cancel()

        await #expect(throws: (any Error).self) { try await refresh.value }
    }

    @Test(arguments: [
        ("codex account authentication required to read rate limits", UsageError.authenticationRequired),
        ("rate limits are unavailable", UsageError.executionFailed("RPC error: rate limits are unavailable")),
    ])
    func `should ask to sign in when a JSON-RPC CLI answers that it is signed out, and report any other error answer as it is (#525)`(
        message: String, expected: UsageError
    ) async throws {
        let transport = MockRPCTransport()
        given(transport).send(.any).willReturn(())
        given(transport).close().willReturn(())
        given(transport).receive().willReturn(Data(#"{"id":1,"error":{"code":-32600,"message":"\#(message)"}}"#.utf8))
        let definition = try decode("""
        {"kind":"rpc","fetch":{"jsonRpc":{"cli":"codex","call":"read",
           "errors":[{"contains":["authentication required"],"error":"authenticationRequired"}]}},
         "mapping":{"json":{"quotas":[]}}}
        """)
        let source = DataSources.make(
            definition,
            providerId: "test",
            cliExecutor: MockCLIExecutor(),
            network: MockNetworkClient(),
            makeTransport: { _, _, _, _ in transport },
            environment: { _ in nil },
            homeDirectory: FileManager.default.temporaryDirectory,
            now: { Date() }
        )

        await #expect(throws: DataSourceError(.fetch, expected)) { try await source.fetchUsage() }
    }

    @Test
    func `should wait fifteen seconds for a JSON-RPC CLI unless the definition says otherwise`() throws {
        let call = try JSONDecoder().decode(JSONRPCCall.self, from: Data(#"{"cli":"codex","call":"read"}"#.utf8))

        #expect(call.timeout == 15)
    }

    // MARK: - The path dialect

    @Test
    func `should find a value from the answer's root, the current item, a response header or the item's key`() {
        let root: [String: Any] = ["a": ["b": 2, "list": [["c": 3]]]]
        let scope = JSONScope(root: root, headers: ["x-used": "7"])
        let inner = scope.moved(to: (root["a"] as? [String: Any]), key: "k")

        #expect(scope.number("$.a.b") == 2)
        #expect(scope.number("$.a.list.0.c") == 3)
        #expect(scope.number("$header.X-Used") == 7)
        #expect(inner.number("b") == 2)
        #expect(inner.string("$key") == "k")
        #expect(scope.moved(to: nil).value("b") == nil)
    }

    @Test
    func `should leave a template's text out when its placeholder has no value`() {
        #expect(Template.fill("Bearer {{token}}", with: Credential(["token": "t"])) == "Bearer t")
        #expect(Template.fill("{{account}}", with: Credential(["token": "t"])) == nil)
        #expect(Template.fill("plain", with: nil) == "plain")
    }
}

/// What the transport factory was asked to start.
private final class StartedProcess: @unchecked Sendable {
    private(set) var executable: String?
    private(set) var arguments: [String]?
    private(set) var directory: URL?

    func record(_ executable: String, _ arguments: [String], _ directory: URL?) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
    }
}

/// A CLI that started but never answers: like a real pipe, a read waits until
/// the transport is closed, and ignores cancellation.
private final class SilentRPCTransport: RPCTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func send(_ data: Data) throws {}

    func receive() async throws -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            if closed { lock.unlock(); continuation.resume(); return }
            waiting.append(continuation)
            lock.unlock()
        }
        throw UsageError.executionFailed("Process closed unexpectedly")
    }

    func close() {
        lock.lock()
        closed = true
        let resumed = waiting
        waiting = []
        lock.unlock()
        resumed.forEach { $0.resume() }
    }
}
