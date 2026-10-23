import Foundation
import Domain

/// THE ROUTES — the closed table between a request and a read, plus the MCP
/// tool list, which is this table read twice: one tool per route, each
/// answering the same payload its HTTP route answers. This is also the one
/// owner of the read-only law: no row here mutates anything.
///
/// Every answer encodes one read of the *All* page's `Overview` — the
/// router never refreshes, never decides, and never holds a number of its own.
public struct LocalAPIRouter: Sendable {
    /// The Overview as it stands now — read on the main actor, where the
    /// Monitor's state lives. The app hands `{ Overview(monitor) }`; tests
    /// hand one built by hand.
    private let read: @MainActor @Sendable () -> Overview
    /// The clock the answers' `updatedAt` reads.
    private let now: @Sendable () -> Date
    /// The version `serverInfo` names — the app's own.
    private let version: String

    /// The n `/usage/days` and `usage_days` clamp to: a year of days is the
    /// most any surface asks the history for.
    public static let usageDaysRange = 1...365

    /// Builds the router. `version` names what `serverInfo` and the index
    /// answer with — the app's short version when nil (tests name their own).
    public init(read: @escaping @MainActor @Sendable () -> Overview, version: String? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.read = read
        self.now = now
        self.version = version ?? Self.bundleVersion
    }

    // MARK: - The four answers, each one read of the Overview

    /// `GET /status` — the one line: the ring All leads with, the overall status.
    func statusSummary() async -> StatusSummary { StatusSummary(await read(), at: now()) }

    /// `GET /providers` — every card's logins: quotas, status, best, inUse.
    func providersReport() async -> ProvidersReport { ProvidersReport(await read(), at: now()) }

    /// `GET /forecast` — every quota that has a forecast line.
    func forecastReport() async -> ForecastReport { ForecastReport(await read(), at: now()) }

    /// `GET /usage/days?n=` — per login, day by day, read on the ask.
    func usageDays(count: Int) async -> UsageDaysReport {
        await UsageDaysReport.read(await read(), count: count, endingOn: now())
    }

    /// The app's short version, as the Settings window shows it.
    static var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// Answers one request — a whole one, or the reason the parser refused
    /// it. Errors are JSON, so a launcher always gets something to read.
    public func answer(_ result: LocalAPIRequestResult) async -> LocalAPIResponse {
        switch result {
        case let .request(request): await answer(request)
        case let .failed(error): Self.response(for: error)
        }
    }

    /// Answers one parsed request from the closed route table.
    public func answer(_ request: LocalAPIRequest) async -> LocalAPIResponse {
        guard Self.isLocalOrigin(request) else {
            return LocalAPIResponse.error(403, "forbidden")
        }
        switch (request.method, request.path) {
        case ("GET", "/"):
            return Self.index(version: version)
        case ("GET", "/status"):
            return .json(await statusSummary())
        case ("GET", "/providers"):
            return .json(await providersReport())
        case ("GET", "/forecast"):
            return .json(await forecastReport())
        case ("GET", "/usage/days"):
            return .json(await usageDays(count: Self.clampedDays(from: request.query["n"])))
        case ("POST", "/mcp"):
            return await answerMCP(request)
        case (_, "/"), (_, "/status"), (_, "/providers"), (_, "/forecast"), (_, "/usage/days"):
            return Self.methodNotAllowed(allowed: "GET")
        case (_, "/mcp"):
            return Self.methodNotAllowed(allowed: "POST")
        default:
            return LocalAPIResponse.error(404, "not found")
        }
    }

    // MARK: - MCP

    /// POST /mcp — one JSON-RPC message in, one JSON answer out. A
    /// notification is answered with 202 and silence; a body that is not one
    /// message is a JSON-RPC error at 400.
    func answerMCP(_ request: LocalAPIRequest) async -> LocalAPIResponse {
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
            MCPTool(name: "quota_status", description: "One line: the quota that runs out first across your AI coding products, each read by its login with the most room, and the overall status. Ask this before starting a big task.") { [self] _ in
                Self.text(await statusSummary())
            },
            MCPTool(name: "providers", description: "Every watched login with its quotas and status, which login has the most left (best), and which one new terminal sessions start with (inUse).") { [self] _ in
                Self.text(await providersReport())
            },
            MCPTool(name: "forecast", description: "Every quota that has a forecast: whether it lasts until it resets at the pace it has been spent, or runs out first, and when.") { [self] _ in
                Self.text(await forecastReport())
            },
            MCPTool(name: "usage_days", description: "Daily usage per login — cost, tokens, cache, working time — for the last n days.", inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["n": .object([
                    "type": .string("integer"),
                    "description": .string("How many days back, 1 to 365. Default 30."),
                ])]),
            ])) { [self] arguments in
                Self.text(await usageDays(count: Self.clampedDays(from: arguments?["n"]?.intValue)))
            },
        ]
    }

    /// The JSON-RPC 2.0 envelope: the id back, and a result or an error.
    static func envelope(id: MCPValue, reply: MCPReply) -> MCPValue {
        var pairs: [String: MCPValue] = ["jsonrpc": .string("2.0"), "id": id]
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
    static func index(version: String) -> LocalAPIResponse {
        .jsonValue(.object([
            "name": .string("claudebar"),
            "version": .string(version),
            "description": .string("Read-only AI coding quota data for this Mac."),
            "endpoints": .array(["/status", "/providers", "/forecast", "/usage/days?n=30"].map { .string($0) }),
            "mcp": .string("/mcp"),
        ]))
    }

    /// Whether the request names this Mac: a `Host` or `Origin` that is
    /// present must be loopback. The peer check stops other machines, not a
    /// browser — a web page can rebind a hostname it owns to `127.0.0.1` and
    /// read the answers same-origin. A header left out is curl's way of
    /// asking; only a named foreign host is turned away.
    static func isLocalOrigin(_ request: LocalAPIRequest) -> Bool {
        func loopback(_ host: String) -> Bool {
            switch host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) {
            case "127.0.0.1", "localhost", "::1": return true
            default: return false
            }
        }
        // `Host` is an authority (host[:port]); `Origin` is a whole URL.
        if let host = request.header("host"),
           !loopback(URL(string: "http://\(host)")?.host ?? host) { return false }
        if let origin = request.header("origin"),
           !loopback(URL(string: origin)?.host ?? origin) { return false }
        return true
    }

    static func methodNotAllowed(allowed: String) -> LocalAPIResponse {
        LocalAPIResponse.error(405, "method not allowed", headers: ["Allow": allowed])
    }

    /// The refusal each parse error earns.
    static func response(for error: LocalAPIParseError) -> LocalAPIResponse {
        switch error {
        case .malformed: LocalAPIResponse.error(400, "malformed request")
        case .oversized: LocalAPIResponse.error(413, "request too large")
        case .chunkedUnsupported: LocalAPIResponse.error(400, "chunked bodies are not supported; send Content-Length")
        case .unsupportedProtocol: LocalAPIResponse.error(505, "only HTTP/1.x is supported")
        }
    }
}
