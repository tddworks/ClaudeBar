import DataSources
import Foundation
import Quotas

/// *Add Provider*'s answers, step by step — *Start from*, *Connect*, *Map
/// fields*, *Look* — turned into a `ProviderDefinition`: the same data a
/// built-in is, run by the same `Provider`. Pure: no I/O, so every step is
/// tested on its own.
public struct ProviderDraft: Sendable, Equatable {
    /// *Start from: API · CLI · File · Copy a provider* — a closed list in the
    /// words Settings prints (USER_JOURNEYS F4).
    public enum Start: Sendable, Equatable {
        case api
        case cli
        case file
        case copy(ProviderDefinition)
    }

    /// *Key lookup order* for an API.
    public enum KeySource: Sendable, Equatable {
        /// *API key* — pasted here, kept in ClaudeBar's vault.
        case apiKey
        /// *Environment variable* — named here, read from the environment.
        case environment(String)
    }

    /// *Sent as*.
    public enum SentAs: Sendable, Equatable {
        /// `Authorization: Bearer <key>`.
        case bearer
        /// `<header>: <key>`.
        case header(String)
    }

    /// *Map fields*: what the numbers mean — *Used · Remaining · Limit*.
    public enum Measure: Sendable, Equatable {
        case percentUsed
        case percentLeft
        /// Money remaining, of a limit or — without one — a balance.
        case money(currency: String)
    }

    public enum ResetsFormat: Sendable, Equatable {
        case iso8601
        case epochSeconds
        case secondsFromNow
    }

    /// What a draft still needs before it can be saved.
    public enum Missing: Error, Sendable, Equatable, LocalizedError {
        case name, url, command, path, used, remaining, textLabel

        public var errorDescription: String? {
            switch self {
            case .name: "Give it a name."
            case .url: "Enter the URL to ask."
            case .command: "Enter the command to run."
            case .path: "Choose the file to read."
            case .used: "Pick the value that says how much is used."
            case .remaining: "Pick the value that says how much is left."
            case .textLabel: "Name the line that holds the number."
            }
        }
    }

    public var start: Start

    // MARK: Connect
    public var url = ""
    public var command = ""
    public var path = ""
    public var key: KeySource? = .apiKey
    public var sentAs: SentAs = .bearer

    // MARK: Map fields
    public var measure: Measure = .percentUsed
    public var used: String?
    public var remaining: String?
    public var limit: String?
    public var resets: String?
    public var resetsFormat: ResetsFormat = .iso8601
    /// For a CLI that prints text: the line that names the percentage.
    public var textLabel: String?
    public var quotaName = "Usage"

    // MARK: Look
    public var name = ""
    public var symbol: String?
    public var color: ProviderLook.Shades?
    public var dashboard: String = ""

    public init(start: Start) {
        self.start = start
        if case .copy(let source) = start {
            name = source.profile.name
        }
    }

    /// The definition this draft describes, under `id` — minted once by the
    /// catalog, never derived from the name alone. Throws what is missing.
    public func definition(id: String) throws -> ProviderDefinition {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Missing.name }

        if case .copy(let source) = start {
            return ProviderDefinition(
                profile: profile(id: id, name: name, links: source.profile.links, base: source.profile.look),
                cli: source.cli,
                dataSources: source.dataSources,
                defaultDataSource: source.defaultDataSource,
                accounts: source.accounts,
                settings: source.settings
            )
        }

        let source = DataSourceDefinition(
            kind: kind,
            label: label,
            summary: summary,
            credential: try credential(),
            fetch: try fetch(),
            mapping: try mapping()
        )
        return ProviderDefinition(
            profile: profile(id: id, name: name, links: links, base: nil),
            cli: cliName,
            dataSources: [source],
            defaultDataSource: kind,
            accounts: try accounts()
        )
    }

    /// *Connect → Test Connection*: the key lookup and the fetch, nothing
    /// mapped yet — so a person sees what comes back before mapping it (F5).
    public func connection() throws -> DataSourceDefinition {
        if case .copy(let source) = start {
            return source.dataSource(source.defaultDataSource) ?? source.dataSources[0]
        }
        return DataSourceDefinition(
            kind: kind, label: label, credential: try credential(), fetch: try fetch(),
            mapping: .json(JSONMapping(quotas: []))
        )
    }

    // MARK: - Private

    private var kind: String {
        switch start {
        case .api: "api"
        case .cli: "cli"
        case .file: "file"
        case .copy(let source): source.defaultDataSource
        }
    }

    private var label: String {
        switch start {
        case .api: "API"
        case .cli: "CLI"
        case .file: "File"
        case .copy: kind
        }
    }

    private var summary: String {
        switch start {
        case .api: "Calls \(url)"
        case .cli: "Runs `\(command)`"
        case .file: "Reads \(path)"
        case .copy: ""
        }
    }

    private var cliName: String? {
        guard case .cli = start else { return nil }
        return Self.words(command).first
    }

    private var links: ProviderDefinition.Links {
        ProviderDefinition.Links(dashboard: URL(string: dashboard.trimmingCharacters(in: .whitespaces)))
    }

    private func profile(id: String, name: String, links: ProviderDefinition.Links, base: ProviderLook?) -> ProviderProfile {
        ProviderProfile(
            id: id,
            name: name,
            links: links,
            look: ProviderLook(
                symbol: symbol ?? base?.symbol,
                icon: base?.icon,
                color: color ?? base?.color,
                gradientEnd: base?.gradientEnd
            ),
            origin: .custom
        )
    }

    /// A key that is the person's own takes a second account by a second
    /// key, typed into *Add Account* and kept under that account. A key read
    /// from an environment variable is the default login's alone.
    private func accounts() throws -> ProviderDefinition.Accounts? {
        guard let credential = try credential() else { return nil }
        var patch: [String: JSONValue] = [:]
        if credential != .setting("apiKey") {
            patch[kind] = try JSONDecoder().decode(JSONValue.self, from: Data(#"{ "credential": { "environment": null, "setting": "apiKey" } }"#.utf8))
        }
        return .init(form: [Setting(id: "apiKey", label: "API key", kind: .secret, scope: .account)], patch: patch)
    }

    private func credential() throws -> CredentialLookup? {
        guard case .api = start, let key else { return nil }
        switch key {
        case .apiKey: return .setting("apiKey")
        case .environment(let variable): return .environment(variable)
        }
    }

    private func fetch() throws -> Fetch {
        switch start {
        case .api:
            let url = url.trimmingCharacters(in: .whitespaces)
            guard !url.isEmpty else { throw Missing.url }
            var headers = ["Accept": "application/json"]
            if key != nil {
                switch sentAs {
                case .bearer: headers["Authorization"] = "Bearer {{token}}"
                case .header(let header): headers[header] = "{{token}}"
                }
            }
            return .http(HTTPRequest(url: url, headers: headers))
        case .cli:
            let words = Self.words(command)
            guard let cli = words.first else { throw Missing.command }
            // A command a person types runs over pipes; a TUI needs a definition's `cli`.
            return .command(CommandCall(cli: cli, args: Array(words.dropFirst()), workingDirectory: .dedicated))
        case .file:
            let path = path.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { throw Missing.path }
            return .file(FileCall(path: path))
        case .copy:
            preconditionFailure("A copy keeps its data sources")
        }
    }

    private func mapping() throws -> Mapping {
        if case .cli = start, let textLabel {
            guard !textLabel.isEmpty else { throw Missing.textLabel }
            let number = #"([0-9]+(?:\.[0-9]+)?)\s*%"#
            let pattern = measure == .percentUsed
                ? TextMapping.QuotaPattern(kind: .time, name: quotaName, label: textLabel, usedPercent: number)
                : TextMapping.QuotaPattern(kind: .time, name: quotaName, label: textLabel, leftPercent: number)
            return .text(TextMapping(quotas: [pattern], whenEmpty: "Could not find \(textLabel)"))
        }

        let resetsAt: [ResetRef] = resets.map { path in
            switch resetsFormat {
            case .iso8601: [.iso8601(path)]
            case .epochSeconds: [.epochSeconds(path)]
            case .secondsFromNow: [.secondsFromNow(path)]
            }
        } ?? []
        let name = NameRule(text: quotaName)

        let rule: QuotaRule
        switch measure {
        case .percentUsed:
            guard let used else { throw Missing.used }
            rule = QuotaRule(kind: .time, name: name, usedPercent: [.path(used)], resetsAt: resetsAt)
        case .percentLeft:
            guard let remaining else { throw Missing.remaining }
            rule = QuotaRule(kind: .time, name: name, leftPercent: [.path(remaining)], resetsAt: resetsAt)
        case .money(let currency):
            guard let remaining else { throw Missing.remaining }
            rule = QuotaRule(
                kind: .time, name: name, resetsAt: resetsAt,
                left: QuotaRule.MoneyLeft(money: .value([.path(remaining)]), of: limit.map { .value([.path($0)]) }, currency: currency)
            )
        }
        return .json(JSONMapping(quotas: [rule]))
    }

    /// A command line split into words, honouring "double" and 'single' quotes.
    static func words(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var inWord = false
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(current); current = ""; inWord = false }
            } else {
                current.append(character)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
