import Foundation

/// WHOSE KEY — the screen's *Key lookup order*. A closed sum, one case per JSON
/// tag; `firstOf` is the order itself, and `refresh` keeps an OAuth token fresh
/// and writes it back where it came from.
///
/// ```json
/// "credential": {
///   "jsonFile": { "path": "~/.codex/auth.json", "token": "$.tokens.access_token" },
///   "refresh":  { "oauth2": { "tokenURL": "…", "clientId": "…", "every": 691200 } }
/// }
/// ```
public indirect enum CredentialLookup: Sendable, Equatable {
    /// An environment variable holds the token.
    case environment(String)
    /// A JSON file on this Mac holds the token and its companions.
    case jsonFile(JSONFileCredential)
    /// A generic-password Keychain item whose password is JSON (or the token
    /// itself, with `"token": "$"`).
    case keychain(KeychainCredential)
    /// A key the person gave ClaudeBar (*API KEY*), kept in its vault.
    case setting(String)
    /// Cookies of a site the person is signed in to in a browser — *COOKIE SOURCE*.
    case browserCookies(BrowserCookieCredential)
    /// A row of another app's own SQLite database, read only.
    case sqlite(SQLiteCredential)
    /// A lookup that answers only when its values match, with fixed values
    /// added — `"match": { "baseURL": "api\\.z\\.ai" }`, `"with": { … }`.
    case refined(CredentialLookup, Refinement)
    /// The first lookup that answers wins.
    case firstOf([CredentialLookup])
    /// A lookup whose token is kept fresh: by an OAuth 2 refresh, or by the
    /// CLI that owns it.
    case refreshing(CredentialLookup, CredentialRefresh)
}

/// `{ "domains": ["{{setting.region.site}}"], "names": ["auth"], "format": "value" }`
/// — the first browser store holding one of the names answers. `value` is the
/// first cookie's value; `header` is `name=value; …` of every one found.
public struct BrowserCookieCredential: Sendable, Equatable, Codable {
    public enum Format: String, Sendable, Equatable, Codable { case value, header }

    /// Matched as suffixes; `{{setting.x}}` is filled in by the provider.
    public let domains: [String]
    public let names: [String]
    public let format: Format

    public init(domains: [String], names: [String], format: Format = .value) {
        self.domains = domains
        self.names = names
        self.format = format
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domains = try container.decode([String].self, forKey: .domains)
        names = try container.decode([String].self, forKey: .names)
        format = try container.decodeIfPresent(Format.self, forKey: .format) ?? .value
    }
}

/// `{ "path": "~/…/state.vscdb", "query": "SELECT value AS token FROM …",
/// "fields": { "token": "$.token" }, "hint": "Sign in again in Acme." }` — the
/// first row's columns, read like a JSON object. The query must not change
/// the database; one that would is refused.
public struct SQLiteCredential: Sendable, Equatable, Codable {
    public let path: String
    public let query: String
    public let fields: [String: String]
    /// What to do when no key answers — the app that owns the database.
    public let hint: String?

    public init(path: String, query: String, fields: [String: String], hint: String? = nil) {
        self.path = path
        self.query = query
        self.fields = fields
        self.hint = hint
    }
}

/// `match`: a value must match its pattern, or the lookup has no key — a
/// token is never sent to a host it wasn't meant for. `with`: fixed values
/// added to what was found; they never replace a found value. `cookies`:
/// named cookies read out of a Cookie-header token.
public struct Refinement: Sendable, Equatable, Codable {
    public let match: [String: String]
    public let with: [String: String]
    /// Cookies read out of a Cookie-header token, each into a value of its
    /// own name — a console's `sec_token` or CSRF cookie. One the header
    /// lacks stays unknown.
    public let cookies: [String]

    public init(match: [String: String] = [:], with: [String: String] = [:], cookies: [String] = []) {
        self.match = match
        self.with = with
        self.cookies = cookies
    }

    /// The named cookies' values in a `name=value; …` header.
    public func cookieValues(in header: String) -> [String: String] {
        var values: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard parts.count == 2, cookies.contains(String(parts[0])), !parts[1].isEmpty else { continue }
            values[String(parts[0])] = String(parts[1])
        }
        return values
    }
}

/// What a lookup found: the token and the values that travel with it
/// (`refreshToken`, `account`, `refreshedAt`, …), by name. A fetch substitutes
/// them into `{{name}}` placeholders. Never logged.
public struct Credential: Sendable, Equatable {
    public var values: [String: String]

    public init(_ values: [String: String]) {
        self.values = values
    }

    public var token: String? { values["token"] }

    public subscript(_ name: String) -> String? {
        get { values[name] }
        set { values[name] = newValue }
    }
}

/// A Keychain item and where in its JSON password each credential value lives.
public struct KeychainCredential: Sendable, Equatable, Codable {
    /// How a password is stored, when not as itself.
    public enum Encoding: String, Sendable, Equatable, Codable {
        /// go-keyring's `go-keyring-base64:<base64>` — the GitHub CLI's, for one.
        case goKeyringBase64
    }

    public let service: String
    /// The item's account, when several logins share a service.
    public let account: String?
    public let encoding: Encoding?
    /// Credential name → JSON path in the password. `token` is required.
    public let fields: [String: String]

    private static let reserved: Set<String> = ["service", "account", "encoding"]

    public init(service: String, account: String? = nil, encoding: Encoding? = nil, fields: [String: String]) {
        self.service = service
        self.account = account
        self.encoding = encoding
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        service = try container.decode(String.self, forKey: TagKey("service"))
        account = try container.decodeIfPresent(String.self, forKey: TagKey("account"))
        encoding = try container.decodeIfPresent(Encoding.self, forKey: TagKey("encoding"))
        var fields: [String: String] = [:]
        for key in container.allKeys where !Self.reserved.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(String.self, forKey: key)
        }
        self.fields = fields
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        try container.encode(service, forKey: TagKey("service"))
        try container.encodeIfPresent(account, forKey: TagKey("account"))
        try container.encodeIfPresent(encoding, forKey: TagKey("encoding"))
        for (name, path) in fields {
            try container.encode(path, forKey: TagKey(name))
        }
    }

    /// The password as stored, read as what it encodes.
    func decoded(_ password: String) -> String {
        guard encoding == .goKeyringBase64, password.hasPrefix("go-keyring-base64:"),
              let data = Data(base64Encoded: String(password.dropFirst("go-keyring-base64:".count))),
              let text = String(data: data, encoding: .utf8) else { return password }
        return text
    }
}

/// A JSON file and where in it each credential value lives. `path` may start
/// with `~/` or `${VARIABLE:-~}/`.
public struct JSONFileCredential: Sendable, Equatable, Codable {
    /// A file holding several logins — one object per key. The record that
    /// has `prefer` answers before one that hasn't, then the `latest` by
    /// that value (a missing one counts as never ending). Field paths are
    /// read inside the record, and a refreshed token is written back into it.
    public struct Record: Sendable, Equatable, Codable {
        public let prefer: String?
        public let latest: String?

        public init(prefer: String? = nil, latest: String? = nil) {
            self.prefer = prefer
            self.latest = latest
        }
    }

    /// `~` expands to the home directory.
    public let path: String
    /// Credential name → JSON path in the file. `token` is required.
    public let fields: [String: String]
    /// Further paths for a field written as a list — the first that answers.
    public let alternatives: [String: [String]]
    public let record: Record?
    /// Values for fields the file lacks — never written back to it.
    public let defaults: [String: String]

    private static let reserved: Set = ["path", "record", "defaults"]

    public init(path: String, fields: [String: String], alternatives: [String: [String]] = [:],
                record: Record? = nil, defaults: [String: String] = [:]) {
        self.path = path
        self.fields = fields
        self.alternatives = alternatives
        self.record = record
        self.defaults = defaults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        path = try container.decode(String.self, forKey: TagKey("path"))
        record = try container.decodeIfPresent(Record.self, forKey: TagKey("record"))
        defaults = try container.decodeIfPresent([String: String].self, forKey: TagKey("defaults")) ?? [:]
        var fields: [String: String] = [:]
        var alternatives: [String: [String]] = [:]
        for key in container.allKeys where !Self.reserved.contains(key.stringValue) {
            if let paths = try? container.decode([String].self, forKey: key), let first = paths.first {
                fields[key.stringValue] = first
                alternatives[key.stringValue] = Array(paths.dropFirst())
            } else {
                fields[key.stringValue] = try container.decode(String.self, forKey: key)
            }
        }
        self.fields = fields
        self.alternatives = alternatives
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        try container.encode(path, forKey: TagKey("path"))
        try container.encodeIfPresent(record, forKey: TagKey("record"))
        if !defaults.isEmpty { try container.encode(defaults, forKey: TagKey("defaults")) }
        for (name, path) in fields {
            if let more = alternatives[name], !more.isEmpty {
                try container.encode([path] + more, forKey: TagKey(name))
            } else {
                try container.encode(path, forKey: TagKey(name))
            }
        }
    }
}

/// How a refused or ageing token is renewed.
public enum CredentialRefresh: Sendable, Equatable {
    /// `{ "oauth2": … }` — ClaudeBar trades the refresh token and writes the
    /// new one back where it was found.
    case oauth2(OAuth2Refresh)
    /// `{ "cli": { "cli": "gemini", "input": "/quit\n" } }` — on a 401, runs
    /// the CLI that owns the credential; it renews its own file, which is
    /// then read again. ClaudeBar never writes it.
    case cli(CLICall)

    /// What to do when it can no longer renew the token.
    var hint: String? {
        if case .oauth2(let refresh) = self { return refresh.hint }
        return nil
    }
}

/// OAuth 2's refresh-token grant (RFC 6749 §6), with the two triggers a
/// provider can ask for: age since the last refresh, and an HTTP status.
public struct OAuth2Refresh: Sendable, Equatable, Codable {
    public let tokenURL: String
    public let clientId: String
    /// Refresh when the credential's `refreshedAt` is older than this many seconds.
    public let every: TimeInterval?
    /// Refresh once, and fetch once more, when the fetch answers one of these.
    public let onStatus: [Int]
    /// Error codes in the token endpoint's answer that mean "log in again".
    public let expiredCodes: [String]
    /// What to tell the person when the session has expired.
    public let hint: String?
    /// `form` (RFC 6749's default) or `json`.
    public let bodyFormat: BodyFormat
    public let scope: String?
    /// Refresh when the credential's `expiresAt` is within `skew` seconds.
    public let dueWhen: Expiry?

    public enum BodyFormat: String, Sendable, Equatable, Codable {
        case form
        case json
    }

    /// When a token expires: the credential value holding the instant, its
    /// unit, and how early to refresh. A missing value means "refresh now",
    /// unless `missingIsDue` is off — a key that never expires.
    public struct Expiry: Sendable, Equatable, Codable {
        public enum Unit: String, Sendable, Equatable, Codable {
            case seconds
            case milliseconds
            /// `2026-07-26T21:03:09.138930Z`, any fraction of a second.
            case iso8601
        }

        public let expiresAt: String
        public let unit: Unit
        public let skew: TimeInterval
        public let missingIsDue: Bool

        public init(expiresAt: String = "expiresAt", unit: Unit = .seconds, skew: TimeInterval = 0, missingIsDue: Bool = true) {
            self.expiresAt = expiresAt
            self.unit = unit
            self.skew = skew
            self.missingIsDue = missingIsDue
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? "expiresAt"
            unit = try container.decodeIfPresent(Unit.self, forKey: .unit) ?? .seconds
            skew = try container.decodeIfPresent(TimeInterval.self, forKey: .skew) ?? 0
            missingIsDue = try container.decodeIfPresent(Bool.self, forKey: .missingIsDue) ?? true
        }
    }

    public init(
        tokenURL: String,
        clientId: String,
        every: TimeInterval? = nil,
        onStatus: [Int] = [],
        expiredCodes: [String] = [],
        hint: String? = nil,
        bodyFormat: BodyFormat = .form,
        scope: String? = nil,
        dueWhen: Expiry? = nil
    ) {
        self.tokenURL = tokenURL
        self.clientId = clientId
        self.every = every
        self.onStatus = onStatus
        self.expiredCodes = expiredCodes
        self.hint = hint
        self.bodyFormat = bodyFormat
        self.scope = scope
        self.dueWhen = dueWhen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokenURL = try container.decode(String.self, forKey: .tokenURL)
        clientId = try container.decode(String.self, forKey: .clientId)
        every = try container.decodeIfPresent(TimeInterval.self, forKey: .every)
        onStatus = try container.decodeIfPresent([Int].self, forKey: .onStatus) ?? []
        expiredCodes = try container.decodeIfPresent([String].self, forKey: .expiredCodes) ?? []
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        bodyFormat = try container.decodeIfPresent(BodyFormat.self, forKey: .bodyFormat) ?? .form
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        dueWhen = try container.decodeIfPresent(Expiry.self, forKey: .dueWhen)
    }
}

// MARK: - JSON

extension CredentialLookup: Codable {
    private static let tags = ["environment", "jsonFile", "keychain", "setting", "browserCookies", "sqlite", "firstOf"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        let base: CredentialLookup
        switch try container.singleTag(of: Self.tags, in: "credential") {
        case "environment":
            base = .environment(try container.decode(String.self, forKey: TagKey("environment")))
        case "jsonFile":
            base = .jsonFile(try container.decode(JSONFileCredential.self, forKey: TagKey("jsonFile")))
        case "keychain":
            base = .keychain(try container.decode(KeychainCredential.self, forKey: TagKey("keychain")))
        case "setting":
            base = .setting(try container.decode(String.self, forKey: TagKey("setting")))
        case "browserCookies":
            base = .browserCookies(try container.decode(BrowserCookieCredential.self, forKey: TagKey("browserCookies")))
        case "sqlite":
            base = .sqlite(try container.decode(SQLiteCredential.self, forKey: TagKey("sqlite")))
        default:
            base = .firstOf(try container.decode([CredentialLookup].self, forKey: TagKey("firstOf")))
        }
        var refined = base
        let match = try container.decodeIfPresent([String: String].self, forKey: TagKey("match")) ?? [:]
        let with = try container.decodeIfPresent([String: String].self, forKey: TagKey("with")) ?? [:]
        let cookies = try container.decodeIfPresent([String].self, forKey: TagKey("cookies")) ?? []
        if !match.isEmpty || !with.isEmpty || !cookies.isEmpty {
            refined = .refined(base, Refinement(match: match, with: with, cookies: cookies))
        }
        if container.contains(TagKey("refresh")) {
            let refresh = try container.nestedContainer(keyedBy: TagKey.self, forKey: TagKey("refresh"))
            if refresh.contains(TagKey("cli")) {
                self = .refreshing(refined, .cli(try refresh.decode(CLICall.self, forKey: TagKey("cli"))))
            } else {
                self = .refreshing(refined, .oauth2(try refresh.decode(OAuth2Refresh.self, forKey: TagKey("oauth2"))))
            }
        } else {
            self = refined
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        try encodeBase(into: &container)
    }

    private func encodeBase(into container: inout KeyedEncodingContainer<TagKey>) throws {
        switch self {
        case .environment(let name):
            try container.encode(name, forKey: TagKey("environment"))
        case .jsonFile(let file):
            try container.encode(file, forKey: TagKey("jsonFile"))
        case .keychain(let item):
            try container.encode(item, forKey: TagKey("keychain"))
        case .setting(let name):
            try container.encode(name, forKey: TagKey("setting"))
        case .browserCookies(let cookies):
            try container.encode(cookies, forKey: TagKey("browserCookies"))
        case .sqlite(let database):
            try container.encode(database, forKey: TagKey("sqlite"))
        case .refined(let base, let refinement):
            try base.encodeBase(into: &container)
            if !refinement.match.isEmpty { try container.encode(refinement.match, forKey: TagKey("match")) }
            if !refinement.with.isEmpty { try container.encode(refinement.with, forKey: TagKey("with")) }
            if !refinement.cookies.isEmpty { try container.encode(refinement.cookies, forKey: TagKey("cookies")) }
        case .firstOf(let lookups):
            try container.encode(lookups, forKey: TagKey("firstOf"))
        case .refreshing(let base, let refresh):
            try base.encodeBase(into: &container)
            var nested = container.nestedContainer(keyedBy: TagKey.self, forKey: TagKey("refresh"))
            switch refresh {
            case .oauth2(let oauth): try nested.encode(oauth, forKey: TagKey("oauth2"))
            case .cli(let call): try nested.encode(call, forKey: TagKey("cli"))
            }
        }
    }
}

extension CredentialLookup {
    /// *KEY LOOKUP ORDER* — where the key is looked for, in order, as a person
    /// would find it: a file path, a Keychain item, `$VARIABLE`. Never a value.
    public var lookupOrder: [String] {
        switch self {
        case .environment(let name): ["$\(name)"]
        case .jsonFile(let file): [file.path]
        case .keychain(let item): ["Keychain “\(item.service)”"]
        case .setting: ["API key saved in ClaudeBar"]
        case .browserCookies(let cookies): ["Browser cookies for \(cookies.domains.first ?? "the site")"]
        case .sqlite(let database): [database.path]
        case .refined(let base, _): base.lookupOrder
        case .firstOf(let lookups): lookups.flatMap(\.lookupOrder)
        case .refreshing(let base, _): base.lookupOrder
        }
    }

    /// What to do when no key answers, or it can no longer be refreshed —
    /// the refresh's hint ("Run `claude` in terminal to log in again.").
    public var hint: String? {
        switch self {
        case .refreshing(let base, let refresh): refresh.hint ?? base.hint
        case .firstOf(let lookups): lookups.lazy.compactMap(\.hint).first
        case .sqlite(let database): database.hint
        case .refined(let base, _): base.hint
        case .environment, .jsonFile, .keychain, .setting, .browserCookies: nil
        }
    }
}
