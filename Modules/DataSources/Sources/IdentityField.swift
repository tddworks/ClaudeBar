import Foundation

/// A field that identifies a login — where its account id or email is read,
/// without asking the vendor. Written as the mapping writes paths and decoded
/// once into what it points at:
///
/// - `"account"` or `"$credential.account"` — a value of the looked-up credential
/// - `"$context.account.email"` — field `email` of the context file `account`
public enum IdentityField: Sendable, Equatable, Hashable, Codable {
    case credential(String)
    case context(file: String, field: String)

    private static let credentialPrefix = "$credential."
    private static let contextPrefix = "$context."

    public init(path: String) throws {
        if path.hasPrefix(Self.contextPrefix) {
            let parts = path.dropFirst(Self.contextPrefix.count).split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "\(path): expected $context.<file>.<field>"))
            }
            self = .context(file: String(parts[0]), field: String(parts[1]))
        } else if path.hasPrefix(Self.credentialPrefix) {
            self = .credential(String(path.dropFirst(Self.credentialPrefix.count)))
        } else {
            self = .credential(path)
        }
    }

    /// The path as a definition writes it. A credential value keeps the bare
    /// name, so existing definitions read and write unchanged.
    public var path: String {
        switch self {
        case .credential(let name): name
        case .context(let file, let field): "\(Self.contextPrefix)\(file).\(field)"
        }
    }

    public init(from decoder: Decoder) throws {
        let path = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(path: path)
        } catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "\(path): expected $context.<file>.<field>"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}
