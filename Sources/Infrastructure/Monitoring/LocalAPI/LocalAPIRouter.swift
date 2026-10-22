import Foundation
import Quotas

/// What the local API answers from — the Monitor's reads, and nothing else.
/// The one port between the wire and the Monitor: it never refreshes, never
/// decides, and never holds a number of its own. Read on the main actor,
/// where the Monitor's state lives.
@MainActor
public protocol LocalAPIReading: Sendable {
    /// `GET /status` — the one line: worst quota, overall status.
    func statusSummary() -> StatusSummary

    /// `GET /providers` — every watched login: quotas, status, best, inUse.
    func providersReport() -> ProvidersReport

    /// `GET /forecast` — every quota that has a forecast line.
    func forecastReport() -> ForecastReport

    /// `GET /usage/days?n=` — per login, day by day. An explicit ask, like a
    /// popover opening: the history is read here and never in the background.
    func usageDays(count: Int) async -> UsageDaysReport
}

/// THE ROUTES — the closed table between a request and a read, plus the MCP
/// tool list, which is this table read twice: one tool per route, each
/// answering the same payload its HTTP route answers. This is also the one
/// owner of the read-only law: no row here mutates anything.
public struct LocalAPIRouter: Sendable {
    private let reading: any LocalAPIReading
    /// The version `serverInfo` names — the app's own.
    private let version: String

    /// The n `/usage/days` and `usage_days` clamp to: a year of days is the
    /// most any surface asks the history for.
    public static let usageDaysRange = 1...365

    /// Builds the router. `version` names what `serverInfo` and the index
    /// answer with — the app's short version when nil (tests name their own).
    public init(reading: any LocalAPIReading, version: String? = nil) {
        self.reading = reading
        self.version = version ?? Self.bundleVersion
    }

    /// The app's short version, as the Settings window shows it.
    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Answers one request — a whole one, or the reason the parser refused
    /// it. Errors are JSON, so a launcher always gets something to read.
    public func answer(_ result: HTTPRequestResult) async -> HTTPResponse {
        switch result {
        case let .request(request): await answer(request)
        case let .failed(error): Self.response(for: error)
        }
    }

    /// Answers one parsed request from the closed route table.
    public func answer(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("GET", "/"):
            return Self.index(version: version)
        case ("GET", "/status"):
            return .json(await reading.statusSummary())
        case ("GET", "/providers"):
            return .json(await reading.providersReport())
        case ("GET", "/forecast"):
            return .json(await reading.forecastReport())
        case ("GET", "/usage/days"):
            return .json(await reading.usageDays(count: Self.clampedDays(from: request.query["n"])))
        case ("POST", "/mcp"):
            return await answerMCP(request)
        case (_, "/"), (_, "/status"), (_, "/providers"), (_, "/forecast"), (_, "/usage/days"):
            return Self.methodNotAllowed(allowed: "GET")
        case (_, "/mcp"):
            return Self.methodNotAllowed(allowed: "POST")
        default:
            return HTTPResponse.error(404, "not found")
        }
    }

    // MARK: - MCP

    /// POST /mcp — one JSON-RPC message in, one JSON answer out. A
    /// notification is answered with 202 and silence; a body that is not one
    /// message is a JSON-RPC error at 400.
    func answerMCP(_ request: HTTPRequest) async -> HTTPResponse {
        let inbound = MCPKernel.decode(request.body)
        switch inbound {
        case let .malformed(code, message):
            return .jsonValue(Self.envelope(id: .null, reply: .error(code: code, message: message)), status: 400)
        case .notification:
            return .accepted
        case let .request(id, method, params):
            let reply = await MCPKernel.handle(
                id: id, method: method, params: params,
                serverInfo: MCPServerInfo(name: "claudebar", version: version),
                tools: tools
            )
            return .jsonValue(Self.envelope(id: id, reply: reply))
        }
    }

    /// The tool table — the route list read twice. Each tool runs the same
    /// read its route runs and answers the same JSON, as text content.
    var tools: [MCPTool] {
        [
            MCPTool(name: "quota_status", description: "One line: the worst quota across your AI coding logins and the overall status. Ask this before starting a big task.") { [reading] _ in
                Self.text(await reading.statusSummary())
            },
            MCPTool(name: "providers", description: "Every watched login with its quotas and status, which login has the most left (best), and which one new terminal sessions start with (inUse).") { [reading] _ in
                Self.text(await reading.providersReport())
            },
            MCPTool(name: "forecast", description: "Every quota that has a forecast: whether it lasts until it resets at the pace it has been spent, or runs out first, and when.") { [reading] _ in
                Self.text(await reading.forecastReport())
            },
            MCPTool(name: "usage_days", description: "Daily usage per login — cost, tokens, cache, working time — for the last n days.", inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["n": .object([
                    "type": .string("integer"),
                    "description": .string("How many days back, 1 to 365. Default 30."),
                ])]),
            ])) { [reading] arguments in
                Self.text(await reading.usageDays(count: Self.clampedDays(from: arguments?["n"]?.intValue)))
            },
        ]
    }

    /// The JSON-RPC 2.0 envelope: the id back, and a result or an error.
    static func envelope(id: JSONValue, reply: MCPReply) -> JSONValue {
        var pairs: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": id]
        switch reply {
        case let .result(value): pairs["result"] = value
        case let .error(code, message):
            pairs["error"] = .object(["code": .number(Double(code)), "message": .string(message)])
        case .none: break
        }
        return .object(pairs)
    }

    // MARK: - Values in, answers out

    /// `n` clamped to the days a history answers: a default of 30, at most a
    /// year, never below one. The query's word, read as a number or not at all.
    public static func clampedDays(from raw: String?) -> Int {
        guard let raw, let asked = Int(raw) else { return 30 }
        return clampedDays(from: asked)
    }

    /// `n` clamped to the days a history answers: a default of 30, at most a
    /// year, never below one.
    public static func clampedDays(from raw: Int?) -> Int {
        guard let raw else { return 30 }
        return min(max(raw, usageDaysRange.lowerBound), usageDaysRange.upperBound)
    }

    /// A payload as the text content a tool call returns.
    static func text<T: Encodable>(_ payload: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// GET / — what this service is and what it answers, for a person who
    /// just pointed curl at it.
    static func index(version: String) -> HTTPResponse {
        .jsonValue(.object([
            "name": .string("claudebar"),
            "version": .string(version),
            "description": .string("Read-only AI coding quota data for this Mac."),
            "endpoints": .array(["/status", "/providers", "/forecast", "/usage/days?n=30"].map { .string($0) }),
            "mcp": .string("/mcp"),
        ]))
    }

    static func methodNotAllowed(allowed: String) -> HTTPResponse {
        HTTPResponse.error(405, "method not allowed", headers: ["Allow": allowed])
    }

    /// The refusal each parse error earns.
    static func response(for error: HTTPParseError) -> HTTPResponse {
        switch error {
        case .malformed: HTTPResponse.error(400, "malformed request")
        case .oversized: HTTPResponse.error(413, "request too large")
        case .chunkedUnsupported: HTTPResponse.error(400, "chunked bodies are not supported; send Content-Length")
        case .unsupportedProtocol: HTTPResponse.error(505, "only HTTP/1.x is supported")
        }
    }
}
