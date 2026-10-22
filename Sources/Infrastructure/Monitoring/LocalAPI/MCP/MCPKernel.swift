import Foundation

/// One tool the MCP surface offers: a name, the words for it, the schema of
/// its arguments, and the read that answers. A tool never mutates — its run
/// builds the same payload its HTTP route answers.
public struct MCPTool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: MCPValue
    /// The read, given the call's arguments (or none). Answers the payload
    /// already encoded as text — `tools/call` returns it as text content.
    public let run: @Sendable (MCPValue?) async -> String

    public init(
        name: String, description: String, inputSchema: MCPValue = .emptyObject,
        run: @escaping @Sendable (MCPValue?) async -> String
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.run = run
    }
}

/// Who is answering — the handshake's `serverInfo`.
public struct MCPServerInfo: Sendable, Equatable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// What one JSON-RPC message deserves back. `.none` is a notification's
/// silence: received, nothing to say — the HTTP layer answers 202.
public enum MCPReply: Sendable {
    case result(MCPValue)
    case error(code: Int, message: String)
    case none
}

/// One inbound message, decoded: a request (has an id), a notification (has
/// none), or the reason it never became either.
public enum MCPInbound: Sendable {
    case request(id: MCPValue, method: String, params: MCPValue)
    case notification(method: String)
    /// Not JSON at all, or not one JSON-RPC message — a batch included
    /// (removed from the protocol in `2025-06-18`; one error object answers).
    case malformed(code: Int, message: String)
}

/// THE MINIMUM MCP — the stateless streamable-HTTP surface: `initialize`,
/// `notifications/initialized`, `ping`, `tools/list`, `tools/call`. No
/// sessions, no SSE, no resources, no prompts: the tools answer questions,
/// and a question wants one JSON answer, not a stream.
public enum MCPKernel {
    /// The protocol revision this surface speaks.
    public static let protocolVersion = "2025-06-18"
    /// The revisions it will echo. A client naming one of these gets it back;
    /// any other gets `protocolVersion`.
    public static let supportedVersions: Set<String> = ["2025-03-26", "2025-06-18"]

    // JSON-RPC 2.0 error codes, the MCP surface's three.
    public static let parseErrorCode = -32700
    public static let invalidRequestCode = -32600
    public static let methodNotFoundCode = -32601
    public static let invalidParamsCode = -32602

    /// The one method that mutates nothing and holds nothing: the client's
    /// keep-alive. Answered so a client never hangs on it.
    static let handledMethods: Set<String> = ["initialize", "ping", "tools/list", "tools/call"]

    /// Decodes one message body into what it is.
    public static func decode(_ body: Data) -> MCPInbound {
        guard let message = MCPValue.parse(body) else {
            return .malformed(code: parseErrorCode, message: "Parse error: the body is not JSON")
        }
        guard case let .object(pairs) = message else {
            return .malformed(code: invalidRequestCode, message: "Invalid Request: one JSON-RPC message at a time")
        }
        guard pairs["jsonrpc"]?.stringValue == "2.0", let method = pairs["method"]?.stringValue else {
            return .malformed(code: invalidRequestCode, message: "Invalid Request: jsonrpc 2.0 and a method are required")
        }
        // A batch (an array) never reaches here — `.parse` yields `.array`,
        // refused above as not an object.
        if let id = pairs["id"], id != .null {
            return .request(id: id, method: method, params: pairs["params"] ?? .emptyObject)
        }
        return .notification(method: method)
    }

    /// Answers one request. Notifications never reach here — the caller
    /// answers them with silence (`MCPReply.none`).
    public static func handle(
        id: MCPValue, method: String, params: MCPValue,
        serverInfo: MCPServerInfo, tools: [MCPTool]
    ) async -> MCPReply {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue
            let version = requested.flatMap { Self.supportedVersions.contains($0) ? $0 : nil } ?? Self.protocolVersion
            return .result(.object([
                "protocolVersion": .string(version),
                "capabilities": .object(["tools": .emptyObject]),
                "serverInfo": .object(["name": .string(serverInfo.name), "version": .string(serverInfo.version)]),
            ]))
        case "ping":
            return .result(.emptyObject)
        case "tools/list":
            return .result(.object(["tools": .array(tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "inputSchema": tool.inputSchema,
                ])
            })]))
        case "tools/call":
            return await Self.call(id: id, params: params, tools: tools)
        default:
            return .error(code: methodNotFoundCode, message: "Method not found: \(method)")
        }
    }

    /// `tools/call` — the one place a name becomes a read. An unknown tool is
    /// a protocol error (`invalid params`); a known one answers text content,
    /// the payload its HTTP route answers.
    static func call(id: MCPValue, params: MCPValue, tools: [MCPTool]) async -> MCPReply {
        guard let name = params["name"]?.stringValue else {
            return .error(code: invalidParamsCode, message: "Invalid params: tools/call needs a tool name")
        }
        guard let tool = tools.first(where: { $0.name == name }) else {
            return .error(code: invalidParamsCode, message: "Unknown tool: \(name)")
        }
        let text = await tool.run(params["arguments"])
        return .result(.object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
        ]))
    }
}
