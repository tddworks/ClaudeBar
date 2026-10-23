import Testing
import Foundation
import Domain
@testable import Infrastructure

/// THE CLOSED ROUTE TABLE: every answer a request can earn, and the one law
/// that nothing here mutates. The MCP surface is this table read twice — the
/// same reads, the same payloads, one tool per route.
@MainActor
@Suite
struct LocalAPIRouterTests {

    /// What the router reads — one hand-built Overview — and the payloads
    /// each route should encode from it.
    private struct Read {
        let overview: Overview
        let now: Date
        var status: StatusSummary { StatusSummary(overview, at: now) }
        var providers: ProvidersReport { ProvidersReport(overview, at: now) }
        var forecast: ForecastReport { ForecastReport(overview, at: now) }
    }

    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    /// A router over one product with one login at 30% — no history, so the
    /// days answer only echoes the count it was asked for.
    private func makeRouter(version: String = "9.9.9") -> (LocalAPIRouter, Read) {
        let quota = UsageQuota(percentRemaining: 30, quotaType: .session, providerId: "acme")
        let overview = Overview(cards: [OverviewCard(id: "acme", name: "Acme", logins: [
            OverviewCard.Login(id: "acme", name: "Acme",
                               snapshot: UsageSnapshot(providerId: "acme", quotas: [quota], capturedAt: now),
                               status: .warning, state: .init()),
        ])])
        let now = self.now
        return (LocalAPIRouter(read: { overview }, version: version, now: { now }), Read(overview: overview, now: now))
    }

    /// A GET request value, whole.
    private func get(_ path: String) -> LocalAPIRequest {
        LocalAPIRequest(method: "GET", path: path)
    }

    /// A POST /mcp request carrying one JSON-RPC message.
    private func postMCP(_ message: String) -> LocalAPIRequest {
        LocalAPIRequest(method: "POST", path: "/mcp", body: Data(message.utf8))
    }

    /// The response body as one JSON object, for reading answers back.
    private func object(_ response: LocalAPIResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    // MARK: - The routes

    @Test func `should answer the index with the service its version and its endpoints`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(get("/"))

        #expect(response.status == 200)
        let index = try object(response)
        #expect(index["name"] as? String == "claudebar")
        #expect(index["version"] as? String == "9.9.9")
        #expect(index["mcp"] as? String == "/mcp")
        #expect(index["endpoints"] as? [String] == ["/status", "/providers", "/forecast", "/usage/days?n=30"])
    }

    @Test func `should answer status with the line the Overview reads`() async throws {
        let (router, reading) = makeRouter()

        let response = await router.answer(get("/status"))

        #expect(response.status == 200)
        #expect(try JSONDecoder().decode(StatusSummary.self, from: response.body) == reading.status)
    }

    @Test func `should answer providers with every card the Overview reads`() async throws {
        let (router, reading) = makeRouter()

        let response = await router.answer(get("/providers"))

        #expect(response.status == 200)
        #expect(try JSONDecoder().decode(ProvidersReport.self, from: response.body) == reading.providers)
    }

    @Test func `should answer forecast with every forecast line the Overview reads`() async throws {
        let (router, reading) = makeRouter()

        let response = await router.answer(get("/forecast"))

        #expect(response.status == 200)
        #expect(try JSONDecoder().decode(ForecastReport.self, from: response.body) == reading.forecast)
    }

    @Test func `should answer usage days with thirty days when none are asked`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(get("/usage/days"))

        #expect(response.status == 200)
        #expect(try object(response)["days"] as? Int == 30)
    }

    @Test func `should answer usage days with the n the query names`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(LocalAPIRequest(method: "GET", path: "/usage/days", query: ["n": "7"]))

        #expect(try object(response)["days"] as? Int == 7)
    }

    @Test func `should clamp a year of days as the most usage days answers`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(LocalAPIRequest(method: "GET", path: "/usage/days", query: ["n": "1000"]))

        #expect(try object(response)["days"] as? Int == 365)
    }

    @Test func `should clamp usage days to never fewer than one`() async throws {
        let (router, _) = makeRouter()

        let none = await router.answer(LocalAPIRequest(method: "GET", path: "/usage/days", query: ["n": "0"]))
        let negative = await router.answer(LocalAPIRequest(method: "GET", path: "/usage/days", query: ["n": "-5"]))

        #expect(try object(none)["days"] as? Int == 1)
        #expect(try object(negative)["days"] as? Int == 1)
    }

    @Test func `should clamp a query n that is not a number to the default`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(LocalAPIRequest(method: "GET", path: "/usage/days", query: ["n": "soon"]))

        #expect(try object(response)["days"] as? Int == 30)
    }

    @Test func `should answer an unknown path with not found`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(get("/quota/write"))

        #expect(response.status == 404)
        #expect(try object(response)["error"] as? String == "not found")
    }

    @Test func `should answer a wrong method with not allowed and the one allowed`() async throws {
        let (router, _) = makeRouter()

        let posted = await router.answer(LocalAPIRequest(method: "POST", path: "/status", body: Data()))
        let gotten = await router.answer(get("/mcp"))

        #expect(posted.status == 405)
        #expect(posted.headers["Allow"] == "GET")
        #expect(gotten.status == 405)
        #expect(gotten.headers["Allow"] == "POST")
    }

    // MARK: - Who may ask

    @Test func `should refuse a request whose host names another machine`() async throws {
        let (router, _) = makeRouter()

        let foreign = LocalAPIRequest(method: "GET", path: "/status", headers: ["host": "evil.example:19848"])
        let rebinding = LocalAPIRequest(method: "GET", path: "/status", headers: ["host": "127.0.0.1.nip.io:19848"])

        for request in [foreign, rebinding] {
            let response = await router.answer(request)
            #expect(response.status == 403)
            #expect(try object(response)["error"] as? String == "forbidden")
        }
    }

    @Test func `should refuse an origin that is not this Mac`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(
            LocalAPIRequest(method: "GET", path: "/status", headers: ["origin": "https://evil.example"])
        )

        #expect(response.status == 403)
    }

    @Test func `should answer a request that names this Mac as its host or origin`() async throws {
        let (router, _) = makeRouter()

        let withPort = LocalAPIRequest(method: "GET", path: "/status", headers: ["host": "127.0.0.1:19848"])
        let ipv6 = LocalAPIRequest(method: "GET", path: "/status", headers: ["host": "[::1]:19848"])
        let named = LocalAPIRequest(method: "GET", path: "/status", headers: ["host": "localhost", "origin": "http://localhost:19848"])

        for request in [withPort, ipv6, named] {
            let response = await router.answer(request)
            #expect(response.status == 200)
        }
    }

    // MARK: - The parse refusals

    @Test func `should answer each unreadable request with its one code`() async throws {
        let (router, _) = makeRouter()

        let malformed = await router.answer(.failed(.malformed))
        let oversized = await router.answer(.failed(.oversized))
        let chunked = await router.answer(.failed(.chunkedUnsupported))
        let unsupported = await router.answer(.failed(.unsupportedProtocol))

        #expect(malformed.status == 400)
        #expect(oversized.status == 413)
        #expect(chunked.status == 400)
        #expect(unsupported.status == 505)
        #expect(try object(chunked)["error"] as? String == "chunked bodies are not supported; send Content-Length")
    }

    // MARK: - The MCP surface

    @Test func `should answer an initialize with the handshake envelope`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#
        ))

        #expect(response.status == 200)
        let envelope = try object(response)
        #expect(envelope["jsonrpc"] as? String == "2.0")
        #expect(envelope["id"] as? Int == 1)
        let result = try #require(envelope["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
    }

    @Test func `should answer a notification with accepted silence`() async {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        ))

        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }

    @Test func `should answer a body that is not JSON with the parse error at bad request`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP("this is not json"))

        #expect(response.status == 400)
        let envelope = try object(response)
        let error = try #require(envelope["error"] as? [String: Any])
        #expect(error["code"] as? Int == MCPKernel.parseErrorCode)
    }

    @Test func `should answer a batch with one invalid request error`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","id":2,"method":"ping"}]"#
        ))

        #expect(response.status == 400)
        let error = try #require(try object(response)["error"] as? [String: Any])
        #expect(error["code"] as? Int == MCPKernel.invalidRequestCode)
    }

    @Test func `should call a tool over MCP and answer the same payload as text`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"usage_days","arguments":{"n":7}}}"#
        ))

        #expect(response.status == 200)
        let result = try #require(try object(response)["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content[0]["type"] as? String == "text")
        let text = try #require(content[0]["text"] as? String)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(payload["days"] as? Int == 7)
    }

    @Test func `should answer an unknown tool with invalid params and never a read`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"refresh_everything"}}"#
        ))

        #expect(response.status == 200)
        let error = try #require(try object(response)["error"] as? [String: Any])
        #expect(error["code"] as? Int == MCPKernel.invalidParamsCode)
        #expect(error["message"] as? String == "Unknown tool: refresh_everything")
    }

    @Test func `should answer an unknown method with method not found`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#
        ))

        let error = try #require(try object(response)["error"] as? [String: Any])
        #expect(error["code"] as? Int == MCPKernel.methodNotFoundCode)
    }

    // MARK: - The tool table

    @Test func `should offer one tool per route in the route order`() {
        let (router, _) = makeRouter()

        #expect(router.tools.map(\.name) == ["quota_status", "providers", "forecast", "usage_days"])
        #expect(router.tools.allSatisfy { !$0.description.isEmpty })
    }

    @Test func `should give the usage days tool a schema naming n`() {
        let (router, _) = makeRouter()

        let schema = router.tools[3].inputSchema

        #expect(schema["type"]?.stringValue == "object")
        #expect(schema["properties"]?["n"]?["type"]?.stringValue == "integer")
    }

    @Test func `should clamp the days a tool call asks for like the route does`() async throws {
        let (router, _) = makeRouter()

        let response = await router.answer(postMCP(
            #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"usage_days","arguments":{"n":1000}}}"#
        ))

        let result = try #require(try object(response)["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content[0]["text"] as? String)
        let payload = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(payload["days"] as? Int == 365)
    }

    // MARK: - The whole pipe

    @Test func `should answer a whole request read off the wire`() async throws {
        let (router, reading) = makeRouter()
        let bytes = Data("GET /status HTTP/1.1\r\nHost: 127.0.0.1:19848\r\nAccept: application/json\r\n\r\n".utf8)
        guard let separator = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            Issue.record("expected a header separator"); return
        }

        let request = try LocalAPIRequestParser.parse(
            headerBlock: bytes[..<separator.lowerBound],
            body: bytes[separator.upperBound...]
        )
        let response = await router.answer(.request(request))
        let wire = LocalAPIResponseSerializer.serialize(response)

        let text = String(decoding: wire, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(try JSONDecoder().decode(StatusSummary.self, from: response.body) == reading.status)
    }

    // MARK: - The n both surfaces clamp

    @Test func `should clamp the days helper itself to one through three hundred sixty five`() {
        #expect(LocalAPIRouter.clampedDays(from: nil as Int?) == 30)
        #expect(LocalAPIRouter.clampedDays(from: nil as String?) == 30)
        #expect(LocalAPIRouter.clampedDays(from: "not a number" as String?) == 30)
        #expect(LocalAPIRouter.clampedDays(from: "30" as String?) == 30)
        #expect(LocalAPIRouter.clampedDays(from: "7" as String?) == 7)
        #expect(LocalAPIRouter.clampedDays(from: 30) == 30)
        #expect(LocalAPIRouter.clampedDays(from: 1) == 1)
        #expect(LocalAPIRouter.clampedDays(from: 365) == 365)
        #expect(LocalAPIRouter.clampedDays(from: 0) == 1)
        #expect(LocalAPIRouter.clampedDays(from: -10) == 1)
        #expect(LocalAPIRouter.clampedDays(from: 366) == 365)
        #expect(LocalAPIRouter.clampedDays(from: 10_000) == 365)
    }
}
