import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

/// `"http": { "steps": […] }` — call A, then B with something A said.
@Suite
struct HTTPStepsTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func decode(_ json: String) throws -> DataSourceDefinition {
        try JSONDecoder().decode(DataSourceDefinition.self, from: Data(json.utf8))
    }

    private func make(_ definition: DataSourceDefinition, network: any NetworkClient, environment: [String: String] = [:]) -> DataSource {
        DataSources.make(definition, providerId: "acme", cliExecutor: MockCLIExecutor(), network: network,
                         makeTransport: { _, _, _, _ in MockRPCTransport() }, environment: { environment[$0] },
                         homeDirectory: FileManager.default.temporaryDirectory, now: { Self.now })
    }

    /// Answers by path, recording what was sent.
    private func network(_ answers: [String: (status: Int, body: String)], sent: Sent) -> MockNetworkClient {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            sent.record(request)
            let path = request.url?.path ?? ""
            let answer = answers[path] ?? (404, "")
            sent.count(path)
            let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
            return (Data(answer.body.utf8), response)
        }
        return network
    }

    private let twoSteps = """
    {"kind":"api","credential":{"environment":"KEY"},
     "fetch":{"http":{"steps":[
       {"name":"project","request":{"url":"https://acme.test/project","headers":{"Authorization":"Bearer {{token}}"}},
        "keep":{"project":"$.project.id"}},
       {"name":"usage","request":{"url":"https://acme.test/usage/{{project}}"}}]}},
     "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
    """

    @Test
    func `a later step is filled with what an earlier step kept`() async throws {
        let sent = Sent()
        let source = make(try decode(twoSteps), network: network([
            "/project": (200, #"{"project":{"id":"p-7"}}"#),
            "/usage/p-7": (200, #"{"used":40}"#),
        ], sent: sent), environment: ["KEY": "k"])

        let usage = try await source.fetchUsage()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 60)
        #expect(sent.paths == ["/project", "/usage/p-7"])
    }

    @Test
    func `the response is every step's answer, by name`() async throws {
        let source = make(try decode(twoSteps), network: network([
            "/project": (200, #"{"project":{"id":"p-7"}}"#),
            "/usage/p-7": (200, #"{"used":40}"#),
        ], sent: Sent()), environment: ["KEY": "k"])

        let response = try await source.fetchResponse()
        let answers = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])

        #expect((answers["project"] as? [String: Any])?["project"] != nil)
        #expect((answers["usage"] as? [String: Any])?["used"] as? Int == 40)
        #expect(response.status == 200)
    }

    @Test
    func `a value is kept from the first path that answers`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"who","request":{"url":"https://acme.test/who"},"keep":{"org":["$.data.org.id","$.org.id"]}},
           {"name":"usage","request":{"url":"https://acme.test/usage?org={{org}}"}}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/who": (200, #"{"org":{"id":42}}"#), "/usage": (200, #"{"used":5}"#)], sent: sent))

        _ = try await source.fetchUsage()

        #expect(sent.query("org", at: "/usage") == "42")
    }

    @Test
    func `a query value that came out empty is left out of the URL`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"who","request":{"url":"https://acme.test/who"},"keep":{"org":"$.org.id"}},
           {"name":"usage","request":{"url":"https://acme.test/usage?org={{org}}&v=1"},"dropEmpty":["org"]}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/who": (200, "{}"), "/usage": (200, #"{"used":5}"#)], sent: sent))

        _ = try await source.fetchUsage()

        #expect(sent.query("org", at: "/usage") == nil)
        #expect(sent.query("v", at: "/usage") == "1")
    }

    @Test
    func `a header filled with a value that came out empty is left out`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"usage","request":{"url":"https://acme.test/usage","headers":{"x-csrf-token":"{{csrf}}","Accept":"*/*"}},
            "dropEmpty":["csrf"]}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/usage": (200, #"{"used":5}"#)], sent: sent))

        _ = try await source.fetchUsage()

        #expect(sent.header("x-csrf-token", at: "/usage") == nil)
        #expect(sent.header("Accept", at: "/usage") == "*/*")
    }

    @Test
    func `a kept value never replaces a credential value`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","credential":{"environment":"KEY"},
         "fetch":{"http":{"steps":[
           {"name":"a","request":{"url":"https://acme.test/a"},"keep":{"token":"$.token"}},
           {"name":"b","request":{"url":"https://acme.test/b","headers":{"Authorization":"Bearer {{token}}"}}}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"b.used"}]}}}
        """), network: network(["/a": (200, #"{"token":"stolen"}"#), "/b": (200, #"{"used":1}"#)], sent: sent),
            environment: ["KEY": "mine"])

        _ = try await source.fetchUsage()

        #expect(sent.header("Authorization", at: "/b") == "Bearer mine")
    }

    @Test
    func `an optional step that fails leaves its value unknown and the fetch goes on`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"project","request":{"url":"https://acme.test/project"},"optional":true,"keep":{"project":"$.id"}},
           {"name":"usage","request":{"url":"https://acme.test/usage","method":"POST","body":"{\\"project\\":\\"{{project}}\\"}"},
            "dropEmpty":["project"]}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/project": (500, ""), "/usage": (200, #"{"used":10}"#)], sent: sent))

        let usage = try await source.fetchUsage()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 90)
        #expect(sent.body(at: "/usage") == "{}")
    }

    @Test(arguments: [(401, "authenticationRequired"), (429, "rateLimited")])
    func `an optional step's refused key or rate limit is never swallowed`(_ status: Int, _ tag: String) async throws {
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"project","request":{"url":"https://acme.test/project"},"optional":true},
           {"name":"usage","request":{"url":"https://acme.test/usage"}}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/project": (status, ""), "/usage": (200, #"{"used":10}"#)], sent: Sent()))

        await #expect { try await source.fetchUsage() } throws: { ($0 as? DataSourceError)?.reason.tag == tag }
    }

    @Test
    func `a step is skipped when the value it would find is already known`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","credential":{"environment":"KEY"},
         "fetch":{"http":{"steps":[
           {"name":"token","request":{"url":"https://acme.test/token"},"unless":"token","keep":{"token":"$.t"}},
           {"name":"usage","request":{"url":"https://acme.test/usage"}}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/usage": (200, #"{"used":5}"#)], sent: sent), environment: ["KEY": "known"])

        _ = try await source.fetchUsage()

        #expect(sent.paths == ["/usage"])
    }

    @Test
    func `a value is kept from text by a pattern`() async throws {
        let sent = Sent()
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"page","request":{"url":"https://acme.test/page"},"keep":{"csrf":{"pattern":"csrf=\\"([a-z0-9]+)\\""}}},
           {"name":"usage","request":{"url":"https://acme.test/usage","headers":{"X-CSRF":"{{csrf}}"}}}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network(["/page": (200, #"<meta csrf="ab12">"#), "/usage": (200, #"{"used":5}"#)], sent: sent))

        _ = try await source.fetchUsage()

        #expect(sent.header("X-CSRF", at: "/usage") == "ab12")
    }

    @Test
    func `a step with attempts tries again after a server error`() async throws {
        let sent = Sent()
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            sent.count(request.url?.path ?? "")
            let status = sent.times("/usage") == 1 ? 503 : 200
            return (Data(#"{"used":20}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        let source = make(try decode("""
        {"kind":"api","fetch":{"http":{"steps":[
           {"name":"usage","request":{"url":"https://acme.test/usage"},"attempts":2}]}},
         "mapping":{"json":{"quotas":[{"kind":"weekly","usedPercent":"usage.used"}]}}}
        """), network: network)

        let usage = try await source.fetchUsage()

        #expect(usage.quota(for: .weekly)?.percentRemaining == 80)
        #expect(sent.times("/usage") == 2)
    }

    @Test
    func `a required step that fails ends the fetch at the fetch step`() async throws {
        let source = make(try decode(twoSteps), network: network(["/project": (500, "")], sent: Sent()),
                          environment: ["KEY": "k"])

        await #expect { try await source.fetchUsage() } throws: { ($0 as? DataSourceError)?.step == .fetch }
    }

    @Test(arguments: [
        #"{"steps":[]}"#,
        #"{"steps":[{"name":"a","request":{"url":"u"}},{"name":"a","request":{"url":"u"}}]}"#,
        #"{"steps":[{"name":"a","request":{"url":"u"},"attempts":9}]}"#,
    ])
    func `steps are refused when empty, named twice or tried too often`(_ http: String) {
        #expect(throws: DecodingError.self) {
            try decode(#"{"kind":"api","fetch":{"http":\#(http)},"mapping":{"json":{"quotas":[]}}}"#)
        }
    }

    @Test
    func `steps encode back under http`() throws {
        let definition = try decode(twoSteps)
        let again = try JSONDecoder().decode(DataSourceDefinition.self, from: JSONEncoder().encode(definition))
        #expect(again == definition)
    }
}

/// What a stubbed network was sent, in order.
final class Sent: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var counts: [String: Int] = [:]

    func record(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    func count(_ path: String) { lock.withLock { counts[path, default: 0] += 1 } }
    func times(_ path: String) -> Int { lock.withLock { counts[path] ?? 0 } }
    var paths: [String] { lock.withLock { requests.compactMap { $0.url?.path } } }

    func header(_ name: String, at path: String) -> String? {
        lock.withLock { requests.last { $0.url?.path == path }?.value(forHTTPHeaderField: name) }
    }

    func query(_ name: String, at path: String) -> String? {
        lock.withLock {
            requests.last { $0.url?.path == path }.flatMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == name }?.value
        }
    }

    func body(at path: String) -> String? {
        lock.withLock { requests.last { $0.url?.path == path }?.httpBody.map { String(decoding: $0, as: UTF8.self) } }
    }
}
