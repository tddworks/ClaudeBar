import Foundation

/// One request off the wire, as a value: the only parts the routes may look
/// at — method, path, query, headers, body. No socket, no callbacks; built by
/// `LocalAPIRequestParser` from raw bytes and answered by `LocalAPIRouter`.
public struct LocalAPIRequest: Sendable, Equatable {
    /// The method as sent — `"GET"`, `"POST"`. The router is the one place
    /// that decides which of the two a route takes.
    public let method: String
    /// The request target's path, undecoded (`/usage/days`).
    public let path: String
    /// The query's key–value pairs, undecoded (`["n": "30"]`).
    public let query: [String: String]
    /// Header names lowercased; the first of a repeated name wins.
    public let headers: [String: String]
    /// The body, whole, as the server accumulated it (capped by
    /// `LocalAPIRequestParser.maxBodyBytes`).
    public let body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// The value of the first header called `name` (case-insensitive).
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// What the server can hand the router: a whole request, or the reason it
/// refused one. The router answers both — the adapter stays dumb.
public enum LocalAPIRequestResult: Sendable, Equatable {
    case request(LocalAPIRequest)
    case failed(LocalAPIParseError)
}

/// Why a request never became a value. Each case has one answer, mapped by
/// `LocalAPIRouter.response(for:)`.
public enum LocalAPIParseError: Error, Sendable, Equatable {
    /// The request line or a header could not be read.
    case malformed
    /// The header block or the body is over the caps.
    case oversized
    /// `Transfer-Encoding: chunked` — not spoken here; curl and every MCP
    /// client send `Content-Length`.
    case chunkedUnsupported
    /// Anything but HTTP/1.x.
    case unsupportedProtocol
}

/// One answer to be written back: status, a few headers, a body. Built by
/// the router, turned into bytes by `LocalAPIResponseSerializer`.
public struct LocalAPIResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// A JSON answer, pretty-printed with sorted keys — the same shape a
    /// person reads in `~/.claudebar/status.json`.
    public static func json(_ payload: some Encodable, status: Int = 200) -> LocalAPIResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else {
            return LocalAPIResponse(status: 500, body: Data("{\"error\": \"could not encode\"}".utf8))
        }
        return LocalAPIResponse(status: status, body: data)
    }

    /// A JSON answer for a value already on the wire's terms (`MCPValue`).
    public static func jsonValue(_ value: MCPValue, status: Int = 200) -> LocalAPIResponse {
        LocalAPIResponse(status: status, body: value.encoded(pretty: true))
    }

    /// `{"error": message}` — the one error shape every refusal shares.
    public static func error(_ status: Int, _ message: String, headers: [String: String] = [:]) -> LocalAPIResponse {
        LocalAPIResponse(status: status, headers: headers, body: Data("{\"error\": \(jsonQuoted(message))}".utf8))
    }

    /// 202 Accepted — the answer to a notification: received, nothing to say.
    public static var accepted: LocalAPIResponse {
        LocalAPIResponse(status: 202)
    }

    private static func jsonQuoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// The bytes a connection has delivered so far, read as one request. The
/// server only moves bytes; when a request is whole, refused or abandoned is
/// decided here, on the parser's caps.
public enum LocalAPIRequestFrame: Sendable, Equatable {
    /// Not whole yet: read more.
    case needMore
    /// One request, or the reason it is refused. Either way, answer it.
    case whole(LocalAPIRequestResult)
    /// The peer hung up before one whole request: nothing to serve.
    case abandoned

    /// What `buffer` is, given whether the peer has finished sending. A
    /// header block or a promised body over the caps is refused without
    /// waiting for it; a length that can't be read is refused, never waited
    /// on; bytes after the promised body are not this request's.
    public static func read(_ buffer: Data, peerDone: Bool) -> LocalAPIRequestFrame {
        if LocalAPIRequestParser.isHeaderOverCap(buffer) { return .whole(.failed(.oversized)) }
        let wanted: Int?
        do {
            wanted = try LocalAPIRequestParser.pendingBodyLength(headerBlockPrefix: buffer)
        } catch {
            return .whole(.failed(.malformed))
        }
        if let wanted {
            if wanted > LocalAPIRequestParser.maxBodyBytes { return .whole(.failed(.oversized)) }
            if let separator = buffer.range(of: LocalAPIRequestParser.headerSeparator),
               buffer.count - separator.upperBound >= wanted {
                let head = buffer.subdata(in: buffer.startIndex..<separator.lowerBound)
                let body = buffer.subdata(in: separator.upperBound..<buffer.index(separator.upperBound, offsetBy: wanted))
                return .whole(request(headerBlock: head, body: body))
            }
        }
        return peerDone ? .abandoned : .needMore
    }

    /// A whole request's bytes, as a value, or the reason the parser refused them.
    private static func request(headerBlock: Data, body: Data) -> LocalAPIRequestResult {
        do {
            return .request(try LocalAPIRequestParser.parse(headerBlock: headerBlock, body: body))
        } catch let error as LocalAPIParseError {
            return .failed(error)
        } catch {
            return .failed(.malformed)
        }
    }
}

/// Bytes ⇄ values. The caps live here, on the wire's edge: a request that
/// cannot be read whole is refused, never half-served.
public enum LocalAPIRequestParser {
    /// The largest header block (request line + headers, to the blank line).
    public static let maxHeaderBytes = 64 * 1024
    /// The largest body. The MCP surface's largest real body is a tool call's
    /// arguments — far below this.
    public static let maxBodyBytes = 1 << 20

    static let headerSeparator = Data("\r\n\r\n".utf8)

    /// How many body bytes the request wants, once its header block is whole:
    /// its `Content-Length`, or none. `nil` while the header block is still
    /// arriving. A length that cannot be read — not a number, negative, or
    /// said twice with two different numbers — is refused, never guessed.
    public static func pendingBodyLength(headerBlockPrefix: Data) throws -> Int? {
        guard let range = headerBlockPrefix.range(of: headerSeparator) else { return nil }
        let headers = String(decoding: headerBlockPrefix[..<range.lowerBound], as: UTF8.self)
        var length: Int?
        for line in headers.split(separator: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            guard let said = Int(parts[1].trimmingCharacters(in: .whitespaces)), said >= 0, length == nil || length == said
            else { throw LocalAPIParseError.malformed }
            length = said
        }
        return length ?? 0
    }

    /// Whether the header block is over the cap: while still arriving — the
    /// server asks so it can refuse without waiting for the blank line — and
    /// just as much once it is complete, so a block that crosses the cap in
    /// the breath its blank line arrives is refused all the same.
    public static func isHeaderOverCap(_ accumulated: Data) -> Bool {
        guard let separator = accumulated.range(of: headerSeparator) else {
            return accumulated.count > maxHeaderBytes
        }
        return separator.lowerBound > maxHeaderBytes
    }

    /// The whole request: its header block and its body, both complete.
    public static func parse(headerBlock: Data, body: Data) throws -> LocalAPIRequest {
        guard body.count <= maxBodyBytes else { throw LocalAPIParseError.oversized }
        let head = String(decoding: headerBlock, as: UTF8.self)
        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        guard let requestLine = lines.first else { throw LocalAPIParseError.malformed }
        lines = lines.dropFirst()

        let parts = requestLine.split(separator: " ")
        guard parts.count == 3 else { throw LocalAPIParseError.malformed }
        guard parts[2].hasPrefix("HTTP/1.") else { throw LocalAPIParseError.unsupportedProtocol }

        let method = String(parts[0])
        guard !method.isEmpty else { throw LocalAPIParseError.malformed }

        let target = String(parts[1])
        guard target.hasPrefix("/") else { throw LocalAPIParseError.malformed }
        let targetParts = target.split(separator: "?", maxSplits: 1)
        let path = String(targetParts[0])
        let query = targetParts.count > 1 ? Self.query(String(targetParts[1])) : [:]

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { throw LocalAPIParseError.malformed }
            let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { throw LocalAPIParseError.malformed }
            if headers[name] == nil {
                headers[name] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        if headers["transfer-encoding"] != nil { throw LocalAPIParseError.chunkedUnsupported }

        return LocalAPIRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    /// The query string's pairs, undecoded; a key with no `=` reads as empty.
    /// Empty parts are kept, so a pair of just `=` reads as no key and is
    /// skipped — never an index out of bounds.
    static func query(_ raw: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0])
            guard !key.isEmpty else { continue }
            pairs[key] = parts.count > 1 ? String(parts[1]) : ""
        }
        return pairs
    }
}

/// The answer as bytes: a status line, the response's own headers plus the
/// three every reply carries, the blank line, the body.
public enum LocalAPIResponseSerializer {
    /// Writes one response. `Content-Length`, `Content-Type` (JSON, when the
    /// response carries a body and names none) and `Connection: close` are
    /// the serializer's — one request per connection, no keep-alive to time out.
    public static func serialize(_ response: LocalAPIResponse) -> Data {
        var head = "HTTP/1.1 \(response.status) \(reasonPhrase(response.status))\r\n"
        var headers = response.headers
        headers["Content-Length"] = "\(response.body.count)"
        if !response.body.isEmpty, headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json; charset=utf-8"
        }
        headers["Connection"] = "close"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + response.body
    }

    /// The reason phrase a client reads beside the code; `"Status"` for any
    /// code this surface never sends.
    public static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 202: "Accepted"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        case 505: "HTTP Version Not Supported"
        default: "Status"
        }
    }
}
