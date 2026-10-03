import DataSources
import Quotas
import CryptoKit
import Foundation

/// A provider as data — what ships in `Resources/Providers/<id>.json` for a
/// built-in, and what *Add Provider* will write for a custom one. Validated
/// when parsed, so a `Provider` is only ever made from a definition that
/// keeps the laws below.
public struct ProviderDefinition: Sendable, Equatable, Codable {
    public struct Links: Sendable, Equatable, Codable {
        /// The dashboard as written — `{{setting.x}}` may fill it per login.
        public let dashboardTemplate: String?
        public let status: URL?
        /// A different dashboard for some plans — `{ "claudeApi": "…" }`. Keyed
        /// by the plan names mapping scripts use (`claudeMax`, `claudePro`,
        /// `claudeApi`) or a badge as written.
        public let dashboardByPlan: [String: URL]

        public init(dashboard: URL? = nil, status: URL? = nil, dashboardByPlan: [String: URL] = [:]) {
            self.init(dashboardTemplate: dashboard?.absoluteString, status: status, dashboardByPlan: dashboardByPlan)
        }

        public init(dashboardTemplate: String?, status: URL? = nil, dashboardByPlan: [String: URL] = [:]) {
            self.dashboardTemplate = dashboardTemplate
            self.status = status
            self.dashboardByPlan = dashboardByPlan
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                dashboardTemplate: try container.decodeIfPresent(String.self, forKey: .dashboard),
                status: try container.decodeIfPresent(URL.self, forKey: .status),
                dashboardByPlan: try container.decodeIfPresent([String: URL].self, forKey: .dashboardByPlan) ?? [:]
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(dashboardTemplate, forKey: .dashboard)
            try container.encodeIfPresent(status, forKey: .status)
            try container.encode(dashboardByPlan, forKey: .dashboardByPlan)
        }

        private enum CodingKeys: String, CodingKey { case dashboard, status, dashboardByPlan }

        /// The dashboard, when it names no setting.
        public var dashboard: URL? { dashboard(filling: [:]) }

        /// The dashboard for the plan the last usage reported, else the
        /// default with a login's settings filled in — `Setting.fills`.
        public func dashboard(for plan: AccountTier?, settings: [String: String] = [:]) -> URL? {
            if let plan, let url = dashboardByPlan[Self.key(for: plan)] { return url }
            return dashboard(filling: settings)
        }

        private func dashboard(filling settings: [String: String]) -> URL? {
            guard var text = dashboardTemplate else { return nil }
            for (name, value) in settings { text = text.replacingOccurrences(of: "{{setting.\(name)}}", with: value) }
            return text.contains("{{") ? nil : URL(string: text)
        }

        static func key(for plan: AccountTier) -> String {
            switch plan {
            case .claudeMax: "claudeMax"
            case .claudePro: "claudePro"
            case .claudeApi: "claudeApi"
            case .custom(let badge): badge
            }
        }
    }

    /// Stable forever: settings, the menu-bar choice and the lineup are keyed by it.
    /// WHO IT IS — the only place an id becomes a face.
    public var profile: ProviderProfile
    /// Stable forever: settings, the menu-bar choice and the lineup are keyed by it.
    public var id: String { profile.id }
    /// The CLI a person would run (`codex`), when there is one.
    public let cli: String?
    public let enabledByDefault: Bool
    public let dataSources: [DataSourceDefinition]
    public let defaultDataSource: String
    /// Logins added beside the default one, and how they differ.
    public let accounts: Accounts?
    /// What it needs from the person — the provider's `SettingsForm`. The
    /// account-scope ones are what *Add Account* asks for.
    public let settings: [Setting]
    /// *TODAY'S USAGE* — how to extract a login's usage history from its
    /// tool's own logs; `nil` when the provider offers none.
    public let usageHistory: UsageLog.Definition?

    /// What *Add Account*'s form asks for: the account-scope settings.
    public var accountSettings: [Setting] { settings.filter { $0.scope == .account } }

    public func setting(_ id: String) -> Setting? { settings.first { $0.id == id } }

    /// The settings the default login uses — those its data sources or
    /// dashboard name, as `{{setting.x}}` or a `setting` lookup. A folder
    /// only an added login has (Kiro's home) is not one of them, so
    /// Settings never shows a field that changes nothing.
    public var defaultLoginSettings: [Setting] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let text = ((try? encoder.encode(dataSources)).map { String(decoding: $0, as: UTF8.self) } ?? "")
            + (profile.links.dashboardTemplate ?? "")
        return settings.filter { setting in
            text.contains("{{setting.\(setting.id)}}") || text.contains("{{setting.\(setting.id).")
                || text.contains("\"setting\":\"\(setting.id)\"")
        }
    }

    /// Logins a person adds beside the default one (Codex, #326). An added
    /// login runs the SAME data sources with `patch` merged in (RFC 7396) and
    /// its saved values filling `{{account.<name>}}` — one definition, never
    /// a copy per login.
    public struct Accounts: Sendable, Equatable, Codable {
        /// How a person adds one: by choosing the folder its login lives in.
        public let folder: Folder?
        /// …or by running the vendor's login into a new folder, which
        /// `folder` then checks — so a sign-in needs a folder rule.
        public let signIn: SignInCall?
        /// …or by filling in the account's own settings — an API key, a
        /// region. Account scope; a secret is kept in the vault, under the
        /// account. Written here or as `settings` with `"scope": "account"`.
        public let form: [Setting]
        /// By data source kind, what an added login changes — its own folder,
        /// its identity check, no fallback to the shared terminal. `null`
        /// leaves that data source out for added logins.
        public let patch: [String: JSONValue]

        /// `{ "savedAs": "codexHome", "default": "${CODEX_HOME:-~/.codex}",
        /// "accountId": { "field": "account", "savedAs": "chatgptAccountId" } }`
        /// — the folder and the login's account id are saved as the account's
        /// values; `notSignedIn` is what a folder without a login says.
        public struct Folder: Sendable, Equatable, Codable {
            public struct AccountId: Sendable, Equatable, Codable {
                /// The field that identifies the login — a credential value,
                /// or a field of a context file (`$context.account.email`).
                public let field: IdentityField
                public let savedAs: String

                public init(field: IdentityField, savedAs: String) {
                    self.field = field
                    self.savedAs = savedAs
                }
            }

            /// A value worked out from the chosen folder rather than read from
            /// it: `prefix` + the first `sha256` hex digits of the folder's
            /// path — how Claude Code names a config folder's Keychain item.
            public struct Derived: Sendable, Equatable, Codable {
                public let prefix: String
                public let sha256: Int

                public init(prefix: String, sha256: Int) {
                    self.prefix = prefix
                    self.sha256 = sha256
                }
            }

            public let savedAs: String
            /// The default login's folder — never added a second time.
            public let `default`: String?
            public let accountId: AccountId
            /// Where the login's email is read. A credential's `email` unless
            /// the definition says otherwise.
            public let email: IdentityField
            /// Values saved beside the folder, by name, for `{{account.<name>}}`.
            public let derived: [String: Derived]
            public let notSignedIn: String?

            public init(
                savedAs: String,
                default folder: String? = nil,
                accountId: AccountId,
                email: IdentityField = .credential("email"),
                derived: [String: Derived] = [:],
                notSignedIn: String? = nil
            ) {
                self.savedAs = savedAs
                self.default = folder
                self.accountId = accountId
                self.email = email
                self.derived = derived
                self.notSignedIn = notSignedIn
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                savedAs = try container.decode(String.self, forKey: .savedAs)
                self.default = try container.decodeIfPresent(String.self, forKey: .default)
                accountId = try container.decode(AccountId.self, forKey: .accountId)
                email = try container.decodeIfPresent(IdentityField.self, forKey: .email) ?? .credential("email")
                derived = try container.decodeIfPresent([String: Derived].self, forKey: .derived) ?? [:]
                notSignedIn = try container.decodeIfPresent(String.self, forKey: .notSignedIn)
            }

            /// The account's values for a chosen folder: the folder, and what
            /// is derived from it.
            public func values(for folder: String) -> [String: String] {
                var values = [savedAs: folder]
                guard !derived.isEmpty else { return values }
                let hash = SHA256.hash(data: Data(folder.utf8)).map { String(format: "%02x", $0) }.joined()
                for (name, rule) in derived {
                    values[name] = rule.prefix + hash.prefix(max(0, rule.sha256))
                }
                return values
            }
        }

        /// The ways *Add Account* offers, easiest first.
        public var ways: [AddAccountWay] {
            [signIn.map { _ in .signIn }, folder.map { _ in .folder }, form.isEmpty ? nil : .form].compactMap { $0 }
        }

        public init(folder: Folder? = nil, signIn: SignInCall? = nil, form: [Setting] = [], patch: [String: JSONValue] = [:]) {
            self.signIn = signIn
            self.form = form
            self.folder = folder
            self.patch = patch
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folder = try container.decodeIfPresent(Folder.self, forKey: .folder)
            signIn = try container.decodeIfPresent(SignInCall.self, forKey: .signIn)
            form = try (container.decodeIfPresent([Setting].self, forKey: .form) ?? []).map(\.inAccountScope)
            if signIn != nil, folder == nil {
                throw DecodingError.dataCorruptedError(forKey: .signIn, in: container,
                    debugDescription: "accounts.signIn needs accounts.folder to check the folder it signs into")
            }
            patch = try container.decodeIfPresent([String: JSONValue].self, forKey: .patch) ?? [:]
        }

        private enum CodingKeys: String, CodingKey { case folder, signIn, form, patch }

        /// The form is written once, as the definition's account-scope
        /// `settings`; `accounts.form` is only read, from files made before.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(folder, forKey: .folder)
            try container.encodeIfPresent(signIn, forKey: .signIn)
            try container.encode(patch, forKey: .patch)
        }
    }

    public init(
        profile: ProviderProfile,
        cli: String? = nil,
        enabledByDefault: Bool = true,
        dataSources: [DataSourceDefinition],
        defaultDataSource: String,
        accounts: Accounts? = nil,
        settings: [Setting] = [],
        usageHistory: UsageLog.Definition? = nil
    ) {
        self.usageHistory = usageHistory
        self.profile = profile
        self.cli = cli
        self.enabledByDefault = enabledByDefault
        self.dataSources = dataSources
        self.defaultDataSource = defaultDataSource
        // One form: the account-scope settings are also what *Add Account* asks.
        let form = accounts?.form ?? []
        let all = settings + form.filter { field in !settings.contains { $0.id == field.id } }
        self.settings = all
        let accountScope = all.filter { $0.scope == .account }
        if let accounts {
            self.accounts = Accounts(folder: accounts.folder, signIn: accounts.signIn, form: accountScope, patch: accounts.patch)
        } else {
            self.accounts = accountScope.isEmpty ? nil : Accounts(form: accountScope)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accounts = try container.decodeIfPresent(Accounts.self, forKey: .accounts)
        let settings = try container.decodeIfPresent([Setting].self, forKey: .settings) ?? []
        // A file says each setting once: at the top, or in the old account form.
        if let twice = accounts?.form.first(where: { field in settings.contains { $0.id == field.id } }) {
            throw DecodingError.dataCorruptedError(forKey: .settings, in: container,
                debugDescription: "Setting '\(twice.id)' is in both settings and accounts.form")
        }
        self.init(
            profile: try container.decode(ProviderProfile.self, forKey: .profile),
            cli: try container.decodeIfPresent(String.self, forKey: .cli),
            enabledByDefault: try container.decodeIfPresent(Bool.self, forKey: .enabledByDefault) ?? true,
            dataSources: try container.decode([DataSourceDefinition].self, forKey: .dataSources),
            defaultDataSource: try container.decode(String.self, forKey: .defaultDataSource),
            accounts: accounts,
            settings: settings,
            usageHistory: try container.decodeIfPresent(UsageLog.Definition.self, forKey: .usageHistory)
        )
        try validateSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encodeIfPresent(cli, forKey: .cli)
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
        try container.encode(dataSources, forKey: .dataSources)
        try container.encode(defaultDataSource, forKey: .defaultDataSource)
        try container.encodeIfPresent(accounts, forKey: .accounts)
        if !settings.isEmpty { try container.encode(settings, forKey: .settings) }
        try container.encodeIfPresent(usageHistory, forKey: .usageHistory)
    }

    enum CodingKeys: String, CodingKey {
        case profile, cli, enabledByDefault, dataSources, defaultDataSource, accounts, settings, usageHistory
    }

    /// Each setting's id is used once.
    private func validateSettings() throws {
        var ids = Set<String>()
        for setting in settings where !ids.insert(setting.id).inserted {
            throw DefinitionError.duplicateSetting(id, setting.id)
        }
    }

    /// Decodes and checks the laws: at least one data source, kinds unique,
    /// the default and every fallback naming one of them.
    public static func parse(_ data: Data, origin: ProviderProfile.Origin = .builtIn) throws -> ProviderDefinition {
        var definition = try JSONDecoder().decode(ProviderDefinition.self, from: data)
        definition.profile.origin = origin
        try definition.validate()
        return definition
    }

    /// The data sources an added login runs: each one with `accounts.patch`
    /// merged in and `{{account.<name>}}` filled from the login's `values`.
    /// A source that needs a value only some sources ask for (`"for"`) is left
    /// out of a login added without it — added for another source. Throws
    /// when a value every source asks for is missing.
    public func dataSources(forAccount values: [String: String]) throws -> [DataSourceDefinition] {
        let patch = accounts?.patch ?? [:]
        return try dataSources.compactMap { source -> DataSourceDefinition? in
            var adapted = source
            if let change = patch[source.kind] {
                if case .null = change { return nil }
                adapted = try source.patched(with: change)
            }
            adapted = try adapted.filled(values, scope: "account")
            if let missing = adapted.unfilled(scope: "account").first {
                if accountSettings.contains(where: { $0.id == missing && !$0.dataSources.isEmpty }) { return nil }
                throw DefinitionError.missingAccountValue(id, missing)
            }
            return adapted
        }
    }

    public func validate() throws {
        guard !dataSources.isEmpty else { throw DefinitionError.noDataSources(id) }
        var kinds = Set<String>()
        for source in dataSources {
            guard kinds.insert(source.kind).inserted else {
                throw DefinitionError.duplicateKind(id, source.kind)
            }
        }
        guard kinds.contains(defaultDataSource) else {
            throw DefinitionError.unknownDataSource(id, defaultDataSource)
        }
        let handOffs = dataSources.flatMap { [$0.fallback?.to].compactMap { $0 } + Array($0.fallbackOn.values) }
        for kind in handOffs where !kinds.contains(kind) {
            throw DefinitionError.unknownDataSource(id, kind)
        }
    }

    public func dataSource(_ kind: String) -> DataSourceDefinition? {
        dataSources.first { $0.kind == kind }
    }

    /// The same definition running `binary` instead of its CLI's name — the
    /// person's *CLI location* (#210). Only the executable changes: every
    /// CLI and JSON-RPC data source keeps its arguments, prompts and
    /// timing, and so does Add Account's sign-in. The value reaches a
    /// subprocess as argv[0], never a shell command line. An empty,
    /// whitespace-only or unchanged name is a no-op.
    public func runningCLI(_ binary: String) throws -> ProviderDefinition {
        let binary = binary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cli, !binary.isEmpty, binary != cli else { return self }
        let sources = try dataSources.map { source -> DataSourceDefinition in
            let fetch = source.fetch.runningCLI(cli, at: binary)
            guard fetch != source.fetch else { return source }
            let json = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(fetch))
            return try source.patched(with: .object(["fetch": json]))
        }
        var accounts = accounts
        if let signIn = accounts?.signIn, signIn.cli == cli {
            accounts = Accounts(
                folder: accounts?.folder,
                signIn: SignInCall(cli: binary, args: signIn.args, homeVariable: signIn.homeVariable,
                                   unset: signIn.unset, timeout: signIn.timeout, alsoAt: signIn.alsoAt),
                form: accounts?.form ?? [],
                patch: accounts?.patch ?? [:]
            )
        }
        return ProviderDefinition(
            profile: profile,
            cli: cli,
            enabledByDefault: enabledByDefault,
            dataSources: sources,
            defaultDataSource: defaultDataSource,
            accounts: accounts,
            settings: settings,
            usageHistory: usageHistory
        )
    }
}

extension Setting {
    /// The same setting, asked for by *Add Account*.
    var inAccountScope: Setting {
        Setting(id: id, label: label, kind: kind, scope: .account, default: self.default)
    }
}

public enum DefinitionError: Error, Sendable, Equatable, LocalizedError {
    case noDataSources(String)
    case duplicateKind(String, String)
    case unknownDataSource(String, String)
    case missingFile(String)
    case missingAccountValue(String, String)
    case duplicateProvider(String)
    case duplicateSetting(String, String)

    public var errorDescription: String? {
        switch self {
        case .noDataSources(let id): "Provider '\(id)' has no data sources"
        case .duplicateKind(let id, let kind): "Provider '\(id)' lists data source '\(kind)' twice"
        case .unknownDataSource(let id, let kind): "Provider '\(id)' names data source '\(kind)', which it doesn't have"
        case .missingFile(let name): "No provider definition named '\(name)'"
        case .missingAccountValue(let id, let name): "A '\(id)' account has no saved '\(name)'"
        case .duplicateProvider(let id): "A provider named '\(id)' already exists"
        case .duplicateSetting(let id, let setting): "Provider '\(id)' lists setting '\(setting)' twice"
        }
    }
}

/// WHO IT IS — name, face and links; data, never a `switch` on id.
public struct ProviderProfile: Sendable, Equatable, Codable {
    /// Where the definition came from — the badge Settings prints.
    public enum Origin: String, Sendable, Equatable, Codable {
        /// "Built in" — shipped in the app.
        case builtIn
        /// "Custom" — made in *Add Provider*, copied or imported.
        case custom
        /// "Extension" — a manifest in `~/.claudebar/extensions/`.
        case `extension`
    }

    /// Stable forever: settings, the menu-bar choice and the lineup are keyed by it.
    public let id: String
    public let name: String
    public let links: ProviderDefinition.Links
    public let look: ProviderLook
    /// Not written in the file: whoever loads it knows where it came from.
    public var origin: Origin

    public init(id: String, name: String, links: ProviderDefinition.Links = .init(), look: ProviderLook = .init(), origin: Origin = .builtIn) {
        self.id = id
        self.name = name
        self.links = links
        self.look = look
        self.origin = origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            links: try container.decodeIfPresent(ProviderDefinition.Links.self, forKey: .links) ?? .init(),
            look: try container.decodeIfPresent(ProviderLook.self, forKey: .look) ?? .init()
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, links, look
    }
}

/// The face — an SF Symbol, an icon in the asset catalog, and a colour with
/// the gradient it runs into, for light and dark. Plain data: the app turns it
/// into colours.
public struct ProviderLook: Sendable, Equatable, Codable {
    /// `[red, green, blue]`, each 0…1, as written in the definition.
    public struct RGB: Sendable, Equatable, Codable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            self.init(try container.decode(Double.self), try container.decode(Double.self), try container.decode(Double.self))
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(red)
            try container.encode(green)
            try container.encode(blue)
        }
    }

    /// One colour per appearance.
    public struct Shades: Sendable, Equatable, Codable {
        public let light: RGB
        public let dark: RGB

        public init(light: RGB, dark: RGB) {
            self.light = light
            self.dark = dark
        }
    }

    public let symbol: String?
    public let icon: String?
    public let color: Shades?
    /// Where the provider's gradient ends; it starts at `color`.
    public let gradientEnd: Shades?

    public init(symbol: String? = nil, icon: String? = nil, color: Shades? = nil, gradientEnd: Shades? = nil) {
        self.symbol = symbol
        self.icon = icon
        self.color = color
        self.gradientEnd = gradientEnd
    }
}

/// A way *Add Account* offers — one per key of a definition's `accounts`.
public enum AddAccountWay: Sendable, Equatable {
    /// *Sign in with browser*
    case signIn
    /// *Choose Signed-in Folder*
    case folder
    /// The account's own settings — *Enter API key*
    case form
}
