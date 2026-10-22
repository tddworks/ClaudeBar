import Crypto
import Foundation

/// A definition read for one account: its values fill `{{account.x}}`. The
/// definition is written once; nothing is copied per account. A data source
/// and a usage history are both read this way.
public protocol DefinitionTemplate: Codable {}

extension DataSourceDefinition: DefinitionTemplate {}
extension UsageLog.Definition: DefinitionTemplate {}

extension DefinitionTemplate {
    /// The definition with every `{{<scope>.<name>}}` in its strings replaced
    /// by `values[name]`. Other placeholders — `{{token}}` — are left for the
    /// fetch; a name the values lack stays, and `unfilled(scope:)` reports it.
    public func filled(_ values: [String: String], scope: String) throws -> Self {
        try Self.decoded(json().mapStrings { Placeholders.fill($0, values, scope: scope) })
    }

    /// The `{{<scope>.<name>}}` names still in the definition, sorted.
    public func unfilled(scope: String) -> [String] {
        guard let json = try? json() else { return [] }
        var names = Set<String>()
        _ = json.mapStrings { text in
            names.formUnion(Placeholders.names(in: text, scope: scope).map { Placeholders.split($0).base })
            return text
        }
        return names.sorted()
    }

    private func json() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))
    }

    private static func decoded(_ json: JSONValue) throws -> Self {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(json))
    }
}

extension DataSourceDefinition {
    /// The data source as an added account's sign-in reaches it (#577): its
    /// reads that name nothing of the account — an environment variable, a
    /// fixed path or Keychain name, browser cookies, an app's own database —
    /// are this Mac's and left out, the rest filled with the account's
    /// values. `nil` when its key or its fetch is only this Mac's.
    public func forAccount(_ values: [String: String]) throws -> DataSourceDefinition? {
        try accountReads()?.filled(values, scope: "account")
    }
}

extension DataSourceDefinition {
    /// The data source without the lookups in its chain that name a value
    /// it wasn't given — a Keychain item named after a folder, for an
    /// account no folder was set for. A lookup on its own is kept, so a
    /// missing value is still reported.
    public func leavingOutLookupsMissingValues(scope: String) -> DataSourceDefinition {
        changing { $0.credential = $0.credential?.leavingOutLookupsMissingValues(scope: scope) }
    }
}

extension CredentialLookup {
    func leavingOutLookupsMissingValues(scope: String) -> CredentialLookup {
        switch self {
        case .firstOf(let lookups):
            let named = lookups.filter { lookup in
                guard case .firstOf = lookup else { return Placeholders.unfilled(in: lookup, scope: scope).isEmpty }
                return true
            }.map { $0.leavingOutLookupsMissingValues(scope: scope) }
            return named.isEmpty ? self : .firstOf(named)
        case .refined(let base, let refinement): return .refined(base.leavingOutLookupsMissingValues(scope: scope), refinement)
        case .refreshing(let base, let refresh): return .refreshing(base.leavingOutLookupsMissingValues(scope: scope), refresh)
        default: return self
        }
    }
}

extension UsageLog.Definition {
    /// The usage history an added account's sign-in reaches: its own logs,
    /// filled with its values — never this Mac's, nor its other apps.
    public func forAccount(_ values: [String: String]) throws -> UsageLog.Definition? {
        try accountReads()?.filled(values, scope: "account")
    }
}

/// `{{<scope>.<name>}}` in a definition's strings.
public enum Placeholders {
    /// The names in `value`'s strings still waiting for a value.
    static func unfilled(in value: some Encodable, scope: String) -> [String] {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) else { return [] }
        var names: [String] = []
        _ = json.mapStrings { names += Self.names(in: $0, scope: scope); return $0 }
        return names
    }

    static func fill(_ text: String, _ values: [String: String], scope: String) -> String {
        var text = text
        for name in names(in: text, scope: scope) {
            let (base, transform) = split(name)
            if let value = values[base], let filled = transformed(value, by: transform) {
                text = text.replacingOccurrences(of: "{{\(scope).\(name)}}", with: filled)
            }
        }
        return text
    }

    /// `folder#sha256.8` → the value's name and what is done to it.
    static func split(_ name: String) -> (base: String, transform: String?) {
        guard let mark = name.firstIndex(of: "#") else { return (name, nil) }
        return (String(name[..<mark]), String(name[name.index(after: mark)...]))
    }

    /// `sha256.N`: the first N hex digits of the value's SHA-256 — how Claude
    /// Code names a config folder's Keychain item. A value that is not a
    /// place yet (`~/…`, `${VAR:-…}`), or an unknown transform, fills
    /// nothing, so the placeholder is reported as unfilled.
    private static func transformed(_ value: String, by transform: String?) -> String? {
        guard let transform else { return value }
        guard !value.hasPrefix("~"), !value.contains("${") else { return nil }
        let parts = transform.split(separator: ".")
        guard parts.count == 2, parts[0] == "sha256", let digits = Int(parts[1]) else { return nil }
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hash.prefix(max(0, digits)))
    }

    /// The `{{<scope>.<name>}}` names in `text`, as written.
    public static func names(in text: String, scope: String) -> [String] {
        let opening = "{{\(scope)."
        var names: [String] = []
        var rest = text[...]
        while let start = rest.range(of: opening), let end = rest[start.upperBound...].range(of: "}}") {
            names.append(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return names
    }
}

extension JSONValue {
    /// The same value with `transform` applied to every string, keys excepted.
    func mapStrings(_ transform: (String) -> String) -> JSONValue {
        switch self {
        case .string(let text): .string(transform(text))
        case .object(let fields): .object(fields.mapValues { $0.mapStrings(transform) })
        case .array(let items): .array(items.map { $0.mapStrings(transform) })
        case .number, .bool, .null: self
        }
    }
}
