import Foundation

/// One data source as data — the JSON a provider definition lists under
/// `dataSources`. No behaviour: `DataSources.make` turns it into a
/// `DataSource` that fetches.
public struct DataSourceDefinition: Sendable, Equatable, Codable {
    /// What the person picks — `rpc`, `api`, `cli` … and the value of the
    /// provider's saved `<id>.probeMode`.
    public let kind: String
    public let label: String?
    public let summary: String?
    /// One sentence Settings shows while this data source is picked — what it
    /// needs that the summary doesn't say.
    public let note: String?
    /// A data source only ever reached as another one's fallback.
    public let hidden: Bool
    public let credential: CredentialLookup?
    public let fetch: Fetch
    public let mapping: Mapping
    /// The data source to try when this one fails, optionally only while a
    /// provider setting allows it.
    public let fallback: Fallback?
    /// Hand-offs by failure: `{ "subscriptionRequired": "cliCost" }` tries
    /// that data source when this one fails that way, before `fallback`.
    public let fallbackOn: [String: String]
    /// Serve the last usage for this long instead of fetching again; a rate
    /// limit is remembered until it passes. Also the provider's background
    /// refresh floor while this data source is active.
    public let cache: Cache?
    /// JSON files the mapping may read — `{ "account": { "path": …, "email": "$.…" } }`.
    public let context: [String: JSONFileCredential]
    /// What to do once when the mapping reports a failure, then try again.
    public let recover: [String: Recovery]
    /// Files that must exist before anything runs — a CLI that finds no
    /// login may open a browser login on its own (#216). Missing: *Key needed*.
    public let requiresFiles: [String]
    /// The credential must belong to this account, before and after the fetch.
    public let identity: Identity?
    /// A background or popover-open refresh must not run this data source
    /// until one explicit refresh has succeeded (#216).
    public let verifyBeforeBackground: Bool
    /// What a refresh that was held back says until then.
    public let unverifiedMessage: String?
    /// What a fact a worker reported means, in the reasons the screen prints:
    /// `http.<status>`, `http.default`, `cli.missing`, `cli.nonzero`,
    /// `cli.failed`. Nothing from the response fills it in.
    public let errors: [ErrorFact: ErrorRef]

    public init(
        kind: String,
        label: String? = nil,
        summary: String? = nil,
        note: String? = nil,
        hidden: Bool = false,
        credential: CredentialLookup? = nil,
        fetch: Fetch,
        mapping: Mapping,
        fallback: Fallback? = nil,
        fallbackOn: [String: String] = [:],
        cache: Cache? = nil,
        context: [String: JSONFileCredential] = [:],
        recover: [String: Recovery] = [:],
        requiresFiles: [String] = [],
        identity: Identity? = nil,
        verifyBeforeBackground: Bool = false,
        unverifiedMessage: String? = nil,
        errors: [ErrorFact: ErrorRef] = [:]
    ) {
        self.kind = kind
        self.label = label
        self.summary = summary
        self.note = note
        self.hidden = hidden
        self.credential = credential
        self.fetch = fetch
        self.mapping = mapping
        self.fallback = fallback
        self.fallbackOn = fallbackOn
        self.cache = cache
        self.context = context
        self.recover = recover
        self.requiresFiles = requiresFiles
        self.identity = identity
        self.verifyBeforeBackground = verifyBeforeBackground
        self.unverifiedMessage = unverifiedMessage
        self.errors = errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        credential = try container.decodeIfPresent(CredentialLookup.self, forKey: .credential)
        fetch = try container.decode(Fetch.self, forKey: .fetch)
        mapping = try container.decode(Mapping.self, forKey: .mapping)
        fallback = try container.decodeIfPresent(Fallback.self, forKey: .fallback)
        fallbackOn = try container.decodeIfPresent([String: String].self, forKey: .fallbackOn) ?? [:]
        cache = try container.decodeIfPresent(Cache.self, forKey: .cache)
        context = try container.decodeIfPresent([String: JSONFileCredential].self, forKey: .context) ?? [:]
        recover = try container.decodeIfPresent([String: Recovery].self, forKey: .recover) ?? [:]
        requiresFiles = try container.decodeIfPresent([String].self, forKey: .requiresFiles) ?? []
        identity = try container.decodeIfPresent(Identity.self, forKey: .identity)
        verifyBeforeBackground = try container.decodeIfPresent(Bool.self, forKey: .verifyBeforeBackground) ?? false
        unverifiedMessage = try container.decodeIfPresent(String.self, forKey: .unverifiedMessage)
        let named = try container.decodeIfPresent([String: ErrorRef].self, forKey: .errors) ?? [:]
        var errors: [ErrorFact: ErrorRef] = [:]
        for (key, error) in named {
            guard let fact = ErrorFact(key) else {
                throw DecodingError.dataCorruptedError(forKey: .errors, in: container,
                    debugDescription: "Unknown error fact '\(key)': use http.<status>, http.default, cli.missing, cli.nonzero or cli.failed")
            }
            errors[fact] = error
        }
        self.errors = errors
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encode(hidden, forKey: .hidden)
        try container.encodeIfPresent(credential, forKey: .credential)
        try container.encode(fetch, forKey: .fetch)
        try container.encode(mapping, forKey: .mapping)
        try container.encodeIfPresent(fallback, forKey: .fallback)
        try container.encode(fallbackOn, forKey: .fallbackOn)
        try container.encodeIfPresent(cache, forKey: .cache)
        try container.encode(context, forKey: .context)
        try container.encode(recover, forKey: .recover)
        try container.encode(requiresFiles, forKey: .requiresFiles)
        try container.encodeIfPresent(identity, forKey: .identity)
        try container.encode(verifyBeforeBackground, forKey: .verifyBeforeBackground)
        try container.encodeIfPresent(unverifiedMessage, forKey: .unverifiedMessage)
        if !errors.isEmpty {
            try container.encode(Dictionary(uniqueKeysWithValues: errors.map { ($0.key.name, $0.value) }), forKey: .errors)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, label, summary, note, hidden, credential, fetch, mapping, fallback, fallbackOn, cache, context,
             recover, requiresFiles, identity, verifyBeforeBackground, unverifiedMessage, errors
    }
}

extension DataSourceDefinition {
    /// What a failure a worker reported means here: the definition's word for
    /// its fact — the status's own, else `http.default` — or the worker's.
    func reason(for failure: any ReportedFailure) -> UsageError {
        guard let fact = failure.fact else { return failure.reason }
        let meaning = errors[fact] ?? fact.broader.flatMap { errors[$0] }
        return meaning?.usageError ?? failure.reason
    }
}

/// A failure a worker reports as a fact, with the reason it gives when the
/// definition says nothing about it.
protocol ReportedFailure: Error, Sendable {
    /// `nil` when no definition may reword it — a 429 stays a rate limit.
    var fact: ErrorFact? { get }
    var reason: UsageError { get }
}

/// A fact a worker reports about a failed fetch — the key of a data source's
/// `errors`. The worker never words it; the definition may.
public enum ErrorFact: Sendable, Hashable {
    /// An HTTP status that is not an answer. 429 is never one: it stays a rate limit.
    case httpStatus(Int)
    /// Any other HTTP status that is not an answer.
    case httpOther
    case cliMissing
    case cliNonzero
    case cliFailed

    /// The fact that covers this one when the definition doesn't name it.
    var broader: ErrorFact? {
        if case .httpStatus = self { return .httpOther }
        return nil
    }

    init?(_ name: String) {
        switch name {
        case "http.default": self = .httpOther
        case "cli.missing": self = .cliMissing
        case "cli.nonzero": self = .cliNonzero
        case "cli.failed": self = .cliFailed
        default:
            guard name.hasPrefix("http."), let status = Int(name.dropFirst(5)), (100..<600).contains(status), status != 429 else {
                return nil
            }
            self = .httpStatus(status)
        }
    }

    var name: String {
        switch self {
        case .httpStatus(let status): "http.\(status)"
        case .httpOther: "http.default"
        case .cliMissing: "cli.missing"
        case .cliNonzero: "cli.nonzero"
        case .cliFailed: "cli.failed"
        }
    }
}

/// `"fallback": "tty"`, or `{ "to": "cli", "enabledBySetting": "cliFallbackEnabled" }`
/// — the setting is read as `<provider>.<name>`, and the fallback is on unless it says no.
public struct Fallback: Sendable, Equatable, Codable {
    public let to: String
    public let enabledBySetting: String?

    public init(to: String, enabledBySetting: String? = nil) {
        self.to = to
        self.enabledBySetting = enabledBySetting
    }

    public init(from decoder: Decoder) throws {
        if let to = try? decoder.singleValueContainer().decode(String.self) {
            self.init(to: to)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            to: try container.decode(String.self, forKey: .to),
            enabledBySetting: try container.decodeIfPresent(String.self, forKey: .enabledBySetting)
        )
    }
}

public struct Cache: Sendable, Equatable, Codable {
    /// Seconds.
    public let ttl: TimeInterval

    public init(ttl: TimeInterval) {
        self.ttl = ttl
    }
}

/// A fix tried once when the mapping reports a failure.
public enum Recovery: Sendable, Equatable, Codable {
    /// Sets one value deep inside a JSON file that already exists — e.g. a
    /// CLI's "trusted folder" flag. `keys` may hold `{{cliDirectory}}`.
    case patchJSONFile(path: String, keys: [String], value: JSONValue)

    private enum Keys: String, CodingKey { case patchJSONFile }
    private enum PatchKeys: String, CodingKey { case path, keys, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let patch = try container.nestedContainer(keyedBy: PatchKeys.self, forKey: .patchJSONFile)
        self = .patchJSONFile(
            path: try patch.decode(String.self, forKey: .path),
            keys: try patch.decode([String].self, forKey: .keys),
            value: try patch.decode(JSONValue.self, forKey: .value)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .patchJSONFile(let path, let keys, let value):
            var patch = container.nestedContainer(keyedBy: PatchKeys.self, forKey: .patchJSONFile)
            try patch.encode(path, forKey: .path)
            try patch.encode(keys, forKey: .keys)
            try patch.encode(value, forKey: .value)
        }
    }
}

/// Whose login this must be: the value `field` points at equals `equals`, or the
/// session is treated as expired with `hint` — a folder signed in to another
/// account never reports that account's usage as this one's.
public struct Identity: Sendable, Equatable, Codable {
    public let field: IdentityField
    public let equals: String
    public let hint: String?

    public init(field: IdentityField, equals: String, hint: String? = nil) {
        self.field = field
        self.equals = equals
        self.hint = hint
    }
}
