import DataSources
import Diagnostics
import Foundation
import Quotas

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
            if let plan, let url = dashboardByPlan[plan.definitionName] { return url }
            return dashboard(filling: settings)
        }

        /// The setting names the dashboard link fills in, as written.
        var settingsRead: [String] {
            dashboardTemplate.map { Placeholders.names(in: $0, scope: "setting") } ?? []
        }

        private func dashboard(filling settings: [String: String]) -> URL? {
            guard var text = dashboardTemplate else { return nil }
            for (name, value) in settings { text = text.replacingOccurrences(of: "{{setting.\(name)}}", with: value) }
            return text.contains("{{") ? nil : URL(string: text)
        }
    }

    /// Stable forever: settings, the menu-bar choice and the lineup are keyed by it.
    /// WHO IT IS — the only place an id becomes a face.
    public var profile: ProviderProfile
    /// Stable forever: settings, the menu-bar choice and the lineup are keyed by it.
    public var id: String { profile.id }
    /// The CLI a person would run (`codex`), when there is one.
    public let cli: String?
    /// Where else this CLI may be when `cli` isn't on the PATH — the copy
    /// a product's own app carries. `cli` lists them after the name.
    public let cliPlaces: [String]
    public let enabledByDefault: Bool
    /// Where the product sits in the lineup by default; none → after the
    /// rest, by name. The person's own order wins (TARGET_ARCHITECTURE §10).
    public let order: Int?
    /// The guest-passes capability (CANONICAL §2.1), declared
    /// `"guestPasses": { "plans": ["claudeMax", "ULTRA"] }`: the plans that can
    /// send passes, `nil` when not declared. The engine runs it at this definition's CLI.
    public let guestPassPlans: [String]?
    public let dataSources: [DataSourceDefinition]
    public let defaultDataSource: String
    /// `"together": true` — every data source answers on each refresh, the
    /// usage is their union in this order, a failed one is left out, and the
    /// refresh fails only when all do: an extension's sections. Otherwise one
    /// data source answers, with its fallback.
    public let together: Bool
    /// Logins added beside the default one, and how they differ.
    public let accounts: Accounts?
    /// What it needs from the person — the provider's `SettingsForm`. The
    /// account-scope ones are what *Add Account* asks for.
    public let settings: [Setting]
    /// *TODAY'S USAGE* — how to extract a login's usage history from its
    /// tool's own logs; `nil` when the provider offers none.
    public let usageHistory: UsageLog.Definition?
    /// What it takes to see this provider's limits, said where an error
    /// would otherwise be — `nil` when the error says enough.
    public let setup: Setup?

    /// *SET UP* — a title, what it takes, and where to start.
    public struct Setup: Sendable, Equatable, Codable {
        public let title: String
        public let text: String
        public let url: URL?
        /// The button that opens `url`, named for what it sets up.
        public let button: String

        public init(title: String, text: String, url: URL? = nil, button: String = "Set up") {
            self.title = title
            self.text = text
            self.url = url
            self.button = button
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(title: try container.decode(String.self, forKey: .title),
                      text: try container.decode(String.self, forKey: .text),
                      url: try container.decodeIfPresent(URL.self, forKey: .url),
                      button: try container.decodeIfPresent(String.self, forKey: .button) ?? "Set up")
        }

        private enum CodingKeys: String, CodingKey { case title, text, url, button }

        /// For a definition with no `setup`: *Set up <name>*, and what failed.
        public static func fallback(for name: String, error: Error?) -> Setup {
            Setup(title: "Set up \(name)", text: error?.localizedDescription ?? "")
        }
    }

    /// What *Add Account*'s form asks for: the account-scope settings.
    public var accountSettings: [Setting] { settings.filter { $0.scope == .account } }

    public func setting(_ id: String) -> Setting? { settings.first { $0.id == id } }

    /// The settings the default login uses — those a data source reads
    /// (`DataSourceDefinition.settingsRead`) or the dashboard link fills in.
    /// A folder only an added login has (Kiro's home) is not one of them, so
    /// Settings never shows a field that changes nothing.
    public var defaultLoginSettings: [Setting] {
        let read = Set(dataSources.flatMap(\.settingsRead)).union(profile.links.settingsRead)
        return settings.filter { setting in read.contains(where: setting.isNamed(by:)) }
    }

    /// How an account is signed in (#577): accounts a person adds beside the
    /// default one, which is signed in on this Mac. Each runs the SAME
    /// definition read for it — its values filling `{{account.<name>}}`, and
    /// nothing of this Mac reached. A key or a folder given on the form is an
    /// account-scope setting and needs nothing here; a folder ClaudeBar
    /// checks, a sign-in, and how the vendor's CLI runs for an added account
    /// are said once, here.
    public struct Accounts: Sendable, Equatable, Codable {
        /// The values an added folder account keeps: its folder and who is
        /// signed in to it.
        public static let folderValue = "folder"
        public static let accountIdValue = "accountId"

        /// *Choose Signed-in Folder*: where the vendor keeps a login, and who
        /// is signed in to it.
        public let folder: Folder?
        /// *Sign in with browser*: the vendor's login run into a new folder,
        /// which `folder` then checks — so a sign-in needs a folder rule.
        public let signIn: SignIn?
        /// How the vendor's CLI runs for an added account — every fetch,
        /// renewal and sign-in, and the lines *In use* writes.
        public let cli: CLISetup?
        /// *Add Account*'s form — the definition's account-scope settings.
        public let form: [Setting]

        /// `{ "default": "${CODEX_HOME:-~/.codex}", "signedInAs": { "file":
        /// "{{account.folder}}/auth.json", "id": "$.tokens.account_id" } }`
        public struct Folder: Sendable, Equatable, Codable {
            /// Where the vendor keeps the default account's login — fills
            /// `{{account.folder}}` for it, and is never added a second time.
            public let `default`: String?
            /// *Signed in as …* — who is signed in, read for every data source.
            public let signedInAs: SignedInAs
            /// What a folder holding no login says; the fix is the vendor's.
            public let notSignedIn: String?

            public init(default folder: String? = nil, signedInAs: SignedInAs, notSignedIn: String? = nil) {
                self.default = folder
                self.signedInAs = signedInAs
                self.notSignedIn = notSignedIn
            }
        }

        /// `{ "args": ["login"] }` — the vendor's login command; its program
        /// is the definition's `cli`, its environment `accounts.cli`.
        public struct SignIn: Sendable, Equatable, Codable {
            public let args: [String]
            /// Seconds to wait for the person to finish in the browser.
            public let timeout: TimeInterval

            public init(args: [String], timeout: TimeInterval = 300) {
                self.args = args
                self.timeout = timeout
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                args = try container.decode([String].self, forKey: .args)
                timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 300
            }
        }

        /// The ways *Add Account* offers, easiest first.
        public var ways: [AddAccountWay] {
            [signIn.map { _ in .signIn }, folder.map { _ in .folder }, form.isEmpty ? nil : .form].compactMap { $0 }
        }

        public init(folder: Folder? = nil, signIn: SignIn? = nil, cli: CLISetup? = nil, form: [Setting] = []) {
            self.folder = folder
            self.signIn = signIn
            self.cli = cli
            self.form = form
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folder = try container.decodeIfPresent(Folder.self, forKey: .folder)
            signIn = try container.decodeIfPresent(SignIn.self, forKey: .signIn)
            cli = try container.decodeIfPresent(CLISetup.self, forKey: .cli)
            form = try (container.decodeIfPresent([Setting].self, forKey: .form) ?? []).map(\.inAccountScope)
            if signIn != nil, folder == nil {
                throw DecodingError.dataCorruptedError(forKey: .signIn, in: container,
                    debugDescription: "accounts.signIn needs accounts.folder to check the folder it signs into")
            }
            if container.contains(.patch) {
                AppLog.providers.warning("accounts.patch is no longer read: an added account reaches only what names it (#577)")
            }
        }

        private enum CodingKeys: String, CodingKey { case folder, signIn, cli, form, patch }

        /// The form is written once, as the definition's account-scope
        /// `settings`; `accounts.form` is only read, from files made before.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(folder, forKey: .folder)
            try container.encodeIfPresent(signIn, forKey: .signIn)
            try container.encodeIfPresent(cli, forKey: .cli)
        }
    }

    public init(
        profile: ProviderProfile,
        cli: String? = nil,
        cliPlaces: [String] = [],
        enabledByDefault: Bool = true,
        dataSources: [DataSourceDefinition],
        defaultDataSource: String,
        together: Bool = false,
        accounts: Accounts? = nil,
        settings: [Setting] = [],
        usageHistory: UsageLog.Definition? = nil,
        setup: Setup? = nil,
        order: Int? = nil,
        guestPassPlans: [String]? = nil
    ) {
        self.order = order
        self.guestPassPlans = guestPassPlans
        self.together = together
        self.usageHistory = usageHistory
        self.setup = setup
        self.profile = profile
        self.cli = cli
        self.cliPlaces = cliPlaces
        self.enabledByDefault = enabledByDefault
        self.dataSources = dataSources
        self.defaultDataSource = defaultDataSource
        // One form: the account-scope settings are also what *Add Account* asks.
        let form = accounts?.form ?? []
        let all = settings + form.filter { field in !settings.contains { $0.id == field.id } }
        self.settings = all
        let accountScope = all.filter { $0.scope == .account }
        if let accounts {
            self.accounts = Accounts(folder: accounts.folder, signIn: accounts.signIn, cli: accounts.cli, form: accountScope)
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
        // `cli` is a name, or the name and the other places it may be.
        let cli = try (try? container.decodeIfPresent(String.self, forKey: .cli)).map { [$0] }
            ?? container.decodeIfPresent([String].self, forKey: .cli) ?? []
        self.init(
            profile: try container.decode(ProviderProfile.self, forKey: .profile),
            cli: cli.first,
            cliPlaces: Array(cli.dropFirst()),
            enabledByDefault: try container.decodeIfPresent(Bool.self, forKey: .enabledByDefault) ?? true,
            dataSources: try container.decode([DataSourceDefinition].self, forKey: .dataSources),
            defaultDataSource: try container.decode(String.self, forKey: .defaultDataSource),
            together: try container.decodeIfPresent(Bool.self, forKey: .together) ?? false,
            accounts: accounts,
            settings: settings,
            usageHistory: try container.decodeIfPresent(UsageLog.Definition.self, forKey: .usageHistory),
            setup: try container.decodeIfPresent(Setup.self, forKey: .setup),
            order: try container.decodeIfPresent(Int.self, forKey: .order),
            guestPassPlans: try container.decodeIfPresent(GuestPassesDeclaration.self, forKey: .guestPasses)?.plans
        )
        try validateSettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        if let cli {
            if cliPlaces.isEmpty { try container.encode(cli, forKey: .cli) }
            else { try container.encode([cli] + cliPlaces, forKey: .cli) }
        }
        try container.encode(enabledByDefault, forKey: .enabledByDefault)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encode(dataSources, forKey: .dataSources)
        try container.encode(defaultDataSource, forKey: .defaultDataSource)
        if together { try container.encode(together, forKey: .together) }
        try container.encodeIfPresent(accounts, forKey: .accounts)
        if !settings.isEmpty { try container.encode(settings, forKey: .settings) }
        try container.encodeIfPresent(usageHistory, forKey: .usageHistory)
        try container.encodeIfPresent(setup, forKey: .setup)
        if let guestPassPlans { try container.encode(GuestPassesDeclaration(plans: guestPassPlans), forKey: .guestPasses) }
    }

    enum CodingKeys: String, CodingKey {
        case profile, cli, enabledByDefault, order, guestPasses, dataSources, defaultDataSource, together, accounts, settings, usageHistory, setup
    }

    /// `"guestPasses": { "plans": [...] }` — no plans named, none can send passes.
    private struct GuestPassesDeclaration: Codable {
        let plans: [String]

        init(plans: [String]) { self.plans = plans }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plans = try container.decodeIfPresent([String].self, forKey: .plans) ?? []
        }
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

    /// The values the default account is read with. It is signed in as this
    /// Mac is: its folder is where the vendor keeps the default login, and
    /// every other value its setting's default.
    public var defaultAccountValues: [String: String] {
        var values: [String: String] = [:]
        for setting in accountSettings where setting.kind != .secret {
            if let value = setting.default, !value.isEmpty { values[setting.id] = value }
        }
        if let folder = accounts?.folder?.default {
            values[Accounts.folderValue] = folder
        }
        return values
    }

    /// The data sources the default account runs — signed in on this Mac, so
    /// every read is reached — filled with `values`.
    public func dataSources(forDefaultAccount values: [String: String]) throws -> [DataSourceDefinition] {
        try dataSources.map {
            try knowingWhoIsSignedIn($0).filled(values, scope: "account").leavingOutLookupsMissingValues(scope: "account")
        }
    }

    /// The data sources an added account runs: what its own sign-in reaches
    /// (#577). Its CLI runs as `accounts.cli` says; a read that names nothing
    /// of the account is this Mac's and left out; a folder account must still
    /// be who it was added as. A source that needs a value only some sources
    /// ask for (`"for"`) is left out of an account added without it. Throws
    /// when a value every source asks for is missing.
    public func dataSources(forAccount values: [String: String]) throws -> [DataSourceDefinition] {
        // A checked folder holds a login only with who it was added as.
        var signedInAs: String?
        if accounts?.folder != nil, values[Accounts.folderValue] != nil {
            guard let accountId = values[Accounts.accountIdValue] else {
                throw DefinitionError.missingAccountValue(id, Accounts.accountIdValue)
            }
            signedInAs = accountId
        }
        return try reads(for: values, signedInAs: signedInAs)
    }

    /// The data sources that say who is signed in to `folder` before it is
    /// added — *Choose Signed-in Folder*: read as an added account, with no
    /// one to check yet.
    public func dataSources(findingWhoIsSignedInTo folder: String) throws -> [DataSourceDefinition] {
        try reads(for: [Accounts.folderValue: folder], signedInAs: nil)
    }

    private func reads(for values: [String: String], signedInAs: String?) throws -> [DataSourceDefinition] {
        try dataSources.compactMap { source -> DataSourceDefinition? in
            var source = knowingWhoIsSignedIn(source)
            if let cli, let setup = accounts?.cli { source = source.runningCLI(cli, with: setup) }
            let named = source.unfilled(scope: "account")
            guard var read = try source.forAccount(values) else { return nil }
            // A folder the account was given, and the data source reads, must still be there.
            read = read.requiring(folderValues.filter(named.contains).compactMap { values[$0] })
            if let signedInAs { read = read.checkingSignedIn(is: signedInAs) }
            if let missing = read.unfilled(scope: "account").first {
                if accountSettings.contains(where: { $0.id == missing && !$0.dataSources.isEmpty }) { return nil }
                throw DefinitionError.missingAccountValue(id, missing)
            }
            return read
        }
    }

    /// The default account's usage history, filled with `values`.
    public func usageHistory(forDefaultAccount values: [String: String]) -> UsageLog.Definition? {
        try? usageHistory?.filled(values, scope: "account")
    }

    /// The usage history an added account reads: its own logs — `nil` when the
    /// logs are this Mac's, or a value is missing.
    public func usageHistory(forAccount values: [String: String]) -> UsageLog.Definition? {
        guard let read = try? usageHistory?.forAccount(values), read.unfilled(scope: "account").isEmpty else { return nil }
        return read
    }

    /// How the vendor's CLI signs in to `folder`: its login, under
    /// `accounts.cli` with the folder as the account's.
    public func signInCall(into folder: String) throws -> SignInCall? {
        guard let cli, let signIn = accounts?.signIn else { return nil }
        let setup = try (accounts?.cli ?? CLISetup()).filled([Accounts.folderValue: folder], scope: "account")
        return SignInCall(cli: cli, args: setup.args + signIn.args, environment: setup.environment, timeout: signIn.timeout)
    }

    /// The account values that are folders: a checked folder, and every
    /// folder given on the form.
    private var folderValues: [String] {
        accountSettings.filter { if case .path = $0.kind { true } else { false } }.map(\.id)
            + (accounts?.folder == nil ? [] : [Accounts.folderValue])
    }

    private func knowingWhoIsSignedIn(_ source: DataSourceDefinition) -> DataSourceDefinition {
        accounts?.folder.map { source.knowing($0.signedInAs) } ?? source
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
    /// CLI and JSON-RPC data source, every credential renewal that runs the
    /// CLI, and Add Account's sign-in keep their arguments, prompts and
    /// timing. The value reaches a subprocess as argv[0], never a shell
    /// command line. An empty, whitespace-only or unchanged name is a no-op.
    public func runningCLI(_ binary: String) throws -> ProviderDefinition {
        let binary = binary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cli, !binary.isEmpty, binary != cli else { return self }
        return ProviderDefinition(
            profile: profile,
            cli: binary,
            cliPlaces: cliPlaces,
            enabledByDefault: enabledByDefault,
            dataSources: dataSources.map { $0.runningCLI(cli, at: binary) },
            defaultDataSource: defaultDataSource,
            together: together,
            accounts: accounts,
            settings: settings,
            usageHistory: usageHistory,
            setup: setup
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
    case notDeletable(String)

    public var errorDescription: String? {
        switch self {
        case .noDataSources(let id): "Provider '\(id)' has no data sources"
        case .duplicateKind(let id, let kind): "Provider '\(id)' lists data source '\(kind)' twice"
        case .unknownDataSource(let id, let kind): "Provider '\(id)' names data source '\(kind)', which it doesn't have"
        case .missingFile(let name): "No provider definition named '\(name)'"
        case .missingAccountValue(let id, let name): "A '\(id)' account has no saved '\(name)'"
        case .duplicateProvider(let id): "A provider named '\(id)' already exists"
        case .duplicateSetting(let id, let setting): "Provider '\(id)' lists setting '\(setting)' twice"
        case .notDeletable(let id): "Provider '\(id)' isn't one you made; turn it off instead"
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

extension AccountTier {
    /// The plan as a definition names it — the well-known plans by the names
    /// mapping scripts use (`claudeMax`, `claudePro`, `claudeApi`), any other
    /// by its badge as written (`ULTRA`).
    var definitionName: String {
        switch self {
        case .claudeMax: "claudeMax"
        case .claudePro: "claudePro"
        case .claudeApi: "claudeApi"
        case .custom(let badge): badge
        }
    }
}
