import Foundation
import Mockable

/// One thing a provider needs from the person — *API KEY*, *REGION*, *CLI
/// DATA FOLDER*. Its **kind** owns the rule a value must keep; its **scope**
/// says whether every login shares it or each login has its own (CANONICAL
/// §1, `SettingsForm`).
///
/// ```json
/// { "id": "region", "label": "Region", "scope": "account", "default": "china",
///   "kind": { "choice": [ { "id": "china", "label": "China", "site": "kimi.com" },
///                         { "id": "international", "label": "International", "site": "kimi.ai" } ] } }
/// ```
///
/// A definition reads it as `{{setting.region}}`, and a value the chosen
/// option carries as `{{setting.region.site}}`; the provider fills both for
/// each login when it makes that login's data sources.
public struct Setting: Sendable, Equatable, Codable, Identifiable {
    public enum Scope: String, Sendable, Equatable, Codable {
        /// The same for every login — kept as `<provider>.<id>`.
        case provider
        /// Each login has its own; *Add Account* asks for it. The default
        /// login's value is the provider-scope one.
        case account
    }

    /// One option of a choice, and the values it carries.
    public struct Option: Sendable, Equatable, Codable, Identifiable {
        public let id: String
        public let label: String
        public let values: [String: String]

        public init(id: String, label: String? = nil, values: [String: String] = [:]) {
            self.id = id
            self.label = label ?? id
            self.values = values
        }

        public init(from decoder: Decoder) throws {
            if let id = try? decoder.singleValueContainer().decode(String.self) {
                self.init(id: id)
                return
            }
            var fields = try decoder.singleValueContainer().decode([String: String].self)
            guard let id = fields.removeValue(forKey: "id") else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A choice option needs an id"))
            }
            self.init(id: id, label: fields.removeValue(forKey: "label"), values: fields)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(values.merging(["id": id, "label": label]) { _, own in own })
        }
    }

    public enum Kind: Sendable, Equatable, Codable {
        /// Free text, optionally matching a pattern.
        case text(pattern: String?)
        /// A key — kept in the vault, never in settings, never a default.
        case secret
        /// One of its options.
        case choice([Option])
        /// A path on this Mac, `~` allowed; optionally one that must exist.
        case path(mustExist: Bool)

        private enum Keys: String, CodingKey { case text, choice, path, pattern, mustExist }

        public init(from decoder: Decoder) throws {
            if let name = try? decoder.singleValueContainer().decode(String.self) {
                switch name {
                case "text": self = .text(pattern: nil)
                case "secret": self = .secret
                case "path": self = .path(mustExist: false)
                default:
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown setting kind '\(name)'"))
                }
                return
            }
            let container = try decoder.container(keyedBy: Keys.self)
            if let options = try container.decodeIfPresent([Option].self, forKey: .choice) {
                self = .choice(options)
            } else if container.contains(.path) {
                let path = try container.nestedContainer(keyedBy: Keys.self, forKey: .path)
                self = .path(mustExist: try path.decodeIfPresent(Bool.self, forKey: .mustExist) ?? false)
            } else {
                let text = try container.nestedContainer(keyedBy: Keys.self, forKey: .text)
                self = .text(pattern: try text.decodeIfPresent(String.self, forKey: .pattern))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .text(nil):
                var container = encoder.singleValueContainer()
                try container.encode("text")
            case .secret:
                var container = encoder.singleValueContainer()
                try container.encode("secret")
            case .text(let pattern?):
                var container = encoder.container(keyedBy: Keys.self)
                var text = container.nestedContainer(keyedBy: Keys.self, forKey: .text)
                try text.encode(pattern, forKey: .pattern)
            case .choice(let options):
                var container = encoder.container(keyedBy: Keys.self)
                try container.encode(options, forKey: .choice)
            case .path(let mustExist):
                var container = encoder.container(keyedBy: Keys.self)
                var path = container.nestedContainer(keyedBy: Keys.self, forKey: .path)
                try path.encode(mustExist, forKey: .mustExist)
            }
        }
    }

    public let id: String
    public let label: String
    public let kind: Kind
    public let scope: Scope
    public let `default`: String?
    /// The data sources that use it (`"for": ["api"]`); empty is all of them.
    /// *Add Account* asks only for what the active data source uses.
    public let dataSources: [String]

    public init(id: String, label: String, kind: Kind = .text(pattern: nil), scope: Scope = .provider,
                default value: String? = nil, for dataSources: [String] = []) {
        self.id = id
        self.label = label
        self.kind = kind
        self.scope = scope
        self.default = kind == .secret ? nil : value
        self.dataSources = dataSources
    }

    /// Whether the data source `kind` uses it.
    public func isUsed(by kind: String) -> Bool {
        dataSources.isEmpty || dataSources.contains(kind)
    }

    private var isSecret: Bool { kind == .secret }

    /// The options, when it is a choice.
    private var options: [Option] {
        if case .choice(let options) = kind { return options }
        return []
    }

    /// The value a form holds for what was typed: the typed text, trimmed;
    /// a blank is the default, or a choice's first option.
    public func value(from typed: String?) -> String {
        let typed = (typed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.isEmpty else { return typed }
        return self.default ?? options.first?.id ?? ""
    }

    /// The folder a login's values name for this setting — only a path
    /// setting names one. *Sign in again in <folder>*, *the folder stays*.
    public func path(in values: [String: String]) -> String? {
        guard case .path = kind else { return nil }
        return values[id]
    }

    /// Whether two logins' values are the same place — only a path can be;
    /// two spellings of one folder are.
    public func isSamePlace(_ value: String, as other: String, paths: any PathChecking) -> Bool {
        guard case .path = kind else { return false }
        return paths.canonical(value) == paths.canonical(other)
    }

    /// What *Add Account* prints when `value` breaks this setting's rule, or
    /// `nil` when it keeps it. An empty value is never kept.
    public func check(_ value: String, paths: any PathChecking) -> String? {
        guard !value.isEmpty else { return "Fill in \(label)." }
        switch kind {
        case .secret:
            return nil
        case .text(let pattern):
            guard let pattern else { return nil }
            return value.range(of: pattern, options: .regularExpression) == nil ? "Enter a valid \(label)." : nil
        case .choice(let options):
            return options.contains { $0.id == value } ? nil : "Choose a \(label) from the list."
        case .path(let mustExist):
            guard value.hasPrefix("/") || value.hasPrefix("~") else { return "Enter a full path for \(label)." }
            return mustExist && !paths.isFolder(value) ? "Choose an existing folder for \(label)." : nil
        }
    }

    /// What `value` fills in a definition: `{{setting.<id>}}`, and for a
    /// choice `{{setting.<id>.<name>}}` for each value its option carries —
    /// keyed by the name after `setting.`. Empty for a secret: a key reaches a
    /// fetch only through its credential lookup.
    public func fills(for value: String?) -> [String: String] {
        let value = self.value(from: value)
        guard !isSecret, !value.isEmpty else { return [:] }
        var fills = [id: value]
        for (name, text) in options.first(where: { $0.id == value })?.values ?? [:] {
            fills["\(id).\(name)"] = text
        }
        return fills
    }

    /// `text` once for every value this setting can fill into it — each
    /// option's, or the default's — so *Import* lists every host a key may
    /// go to. Unchanged when it names no such setting.
    public func expanding(_ text: String) -> [String] {
        guard text.contains("{{setting.\(id)") else { return [text] }
        let possible = if case .choice(let options) = kind { options.map { fills(for: $0.id) } } else { [fills(for: nil)] }
        return possible.map { fills in
            fills.reduce(text) { $0.replacingOccurrences(of: "{{setting.\($1.key)}}", with: $1.value) }
        }
    }

    /// A login's own value among its saved values — only an account-scope
    /// setting has one; a provider-scope one is the provider's alone.
    public func ownValue(in values: [String: String]) -> String? {
        scope == .account ? values[id] : nil
    }

    /// Puts `value` where this setting keeps it: a secret with the keys for
    /// the vault, anything else with the saved values.
    public func keep(_ value: String, in entry: inout SettingEntry) {
        if isSecret { entry.secrets[id] = value } else { entry.values[id] = value }
    }

    // MARK: - JSON

    private enum CodingKeys: String, CodingKey { case id, label, kind, scope, `default`, secret, choices, `for` }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let kind: Kind
        if let declared = try container.decodeIfPresent(Kind.self, forKey: .kind) {
            kind = declared
        } else if try container.decodeIfPresent(Bool.self, forKey: .secret) == true {
            // The form before kinds: `"secret": true`, `"choices": […]`.
            kind = .secret
        } else if let choices = try container.decodeIfPresent([String].self, forKey: .choices) {
            kind = .choice(choices.map { Option(id: $0) })
        } else {
            kind = .text(pattern: nil)
        }
        let value = try container.decodeIfPresent(String.self, forKey: .default)
        if kind == .secret, value != nil {
            throw DecodingError.dataCorruptedError(forKey: .default, in: container,
                debugDescription: "Setting '\(id)' is a secret, so it has no default")
        }
        self.init(
            id: id,
            label: try container.decode(String.self, forKey: .label),
            kind: kind,
            scope: try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .provider,
            default: value,
            for: try container.decodeIfPresent([String].self, forKey: .for) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(kind, forKey: .kind)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(self.default, forKey: .default)
        if !dataSources.isEmpty { try container.encode(dataSources, forKey: .for) }
    }
}

/// What a filled form keeps: saved values, and keys for the vault.
public struct SettingEntry: Sendable, Equatable {
    public var values: [String: String] = [:]
    public var secrets: [String: String] = [:]

    public init() {}
}

/// What a path setting asks of this Mac — the port its rule reads through.
@Mockable
public protocol PathChecking: Sendable {
    /// Whether `path` (`~` allowed) is an existing folder.
    func isFolder(_ path: String) -> Bool
    /// The same place written one way, symlinks resolved, so two spellings
    /// of one folder compare equal.
    func canonical(_ path: String) -> String
}

/// The real file system.
public struct DiskPaths: PathChecking {
    public init() {}

    public func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: canonical(path), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public func canonical(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
