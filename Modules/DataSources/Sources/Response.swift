import Foundation

/// What came back from a fetch, before anyone read it — the *Response* the
/// Map fields step shows. A fetch produces one; a mapping reads one.
public struct Response: Sendable, Equatable {
    /// The HTTP status, when the fetch was over HTTP.
    public let status: Int?
    /// Header names are lowercased so a mapping can ask case-insensitively.
    public let headers: [String: String]
    public let body: Data

    public init(status: Int? = nil, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.body = body
    }

    public init(text: String) {
        self.init(body: Data(text.utf8))
    }

    public var text: String {
        String(decoding: body, as: UTF8.self)
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}
