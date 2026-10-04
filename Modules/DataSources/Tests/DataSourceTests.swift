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
    func `a definition decodes its three closed sums by tag`() throws {
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
    func `a fetch with two tags is refused`() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"x","fetch":{"http":{"url":"u"},"cli":{"cli":"c"}},"mapping":{"json":{"quotas":[]}}}"#)
        }
    }

    // MARK: - Fetching usage

    @Test
    func `an api key from the environment is sent as the placeholder says`() async throws {
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
    func `test connection stops before mapping`() async throws {
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
    func `a missing key fails at the lookup step`() async throws {
        let source = make(try decode("""
        {"kind":"api","credential":{"environment":"KEY"},"fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[]}}}
        """))

        #expect(await source.isReady() == false)
        await #expect(throws: DataSourceError(.lookup, .authenticationRequired)) { try await source.fetchUsage() }
    }

    @Test
    func `a refused request fails at the fetch step`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), network: http("", status: 500))

        await #expect(throws: DataSourceError(.fetch, .executionFailed("HTTP error: 500"))) { try await source.fetchUsage() }
    }

    @Test
    func `a rate limit carries when to try again`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), network: http("", status: 429, headers: ["Retry-After": "120"]))

        await #expect(throws: DataSourceError(.fetch, .rateLimited(retryAt: Date(timeIntervalSince1970: 1_700_000_120)))) {
            try await source.fetchUsage()
        }
    }

    @Test
    func `a response that is not json fails at the mapping step`() async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},"mapping":{"json":{"quotas":[]}}}
        """), network: http("<html>"))

        await #expect(throws: DataSourceError(.mapping, .parseFailed("Response is not JSON"))) { try await source.fetchUsage() }
    }

    // MARK: - Mapping

    @Test
    func `a balance maps to money with no reset`() throws {
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
    func `a repeated quota is named from the response and tidied`() throws {
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
    func `a reset in seconds from now becomes a date and a countdown`() throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"url":"https://example.com"}},
         "mapping":{"json":{"quotas":[{"kind":"session","usedPercent":"used","resetsAt":{"secondsFromNow":"in"}}]}}}
        """))

        let quota = try source.read(Response(text: #"{"used":10,"in":5400}"#)).quota(for: .session)

        #expect(quota?.resetsAt == Date(timeIntervalSince1970: 1_700_005_400))
        #expect(quota?.resetText == "Resets in 1h 30m")
    }

    @Test
    func `a screen's error phrase wins over its numbers`() throws {
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
    func `a json rpc fetch starts the cli in the probe directory`() async throws {
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

    // MARK: - The path dialect

    @Test
    func `paths read from the root, the current object, a header and a key`() {
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
    func `a placeholder with no value leaves the text out`() {
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
