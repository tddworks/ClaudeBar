import Foundation
import Quotas
import DataSources
import Providers
import Monitoring
import Leaderboard
import Activity
import Alerting
import LocalAPI

/// Every module's settings in `~/.claudebar/settings.json`: providers and their
/// logins, hooks, the local API, Notify!, webhooks, quota alerts, recaps, the
/// leaderboard, Rest when empty. The App's own settings are the App's
/// (`AppSettingsFile`), written through the same `JSONSettingsStore`.
///
/// Backed by `JSONSettingsStore` reading/writing `~/.claudebar/settings.json`.
/// Notify! credentials use the injected secure store; legacy provider
/// credentials remain in UserDefaults pending their own migrations.
final class JSONSettingsRepository:
    SettingsFile,
    HookSettingsRepository,
    LocalAPISettingsRepository,
    NotifySettingsRepository,
    QuotaAlertSettingsRepository,
    WebhookSettingsRepository,
    RecapSentRepository,
    @unchecked Sendable
{
    /// Shared instance using the default settings file
    static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore
    private let credentials: UserDefaults
    private let secureCredentials: any CredentialRepository

    /// The destinations' secrets — Notify!'s token, the webhooks' URLs — in the
    /// Keychain, falling back to the app credential store.
    let destinationSecrets: any DestinationSecrets

    init(
        store: JSONSettingsStore,
        credentials: UserDefaults = .standard,
        secureCredentials: any CredentialRepository = KeychainCredentialRepository.shared
    ) {
        self.store = store
        self.credentials = credentials
        self.secureCredentials = secureCredentials
        self.destinationSecrets = KeychainDestinationSecrets(
            keychain: secureCredentials,
            fallback: UserDefaultsCredentialRepository(defaults: credentials)
        )
    }

    // MARK: - ProviderSettingsRepository

    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        store.read(key: "providers.\(id).isEnabled") ?? defaultValue
    }

    /// Same key the Claude and Codex cards write (`<id>.probeMode`), so a
    /// mode picked before the data-source redesign still applies.
    func dataSourceKind(forProvider id: String) -> String? {
        store.read(key: "\(id).probeMode")
    }

    func setDataSourceKind(_ kind: String, forProvider id: String) {
        store.write(value: kind, key: "\(id).probeMode")
    }

    func cliPath(forProvider id: String) -> String? {
        store.read(key: "providers.\(id).cliPath")
    }

    func setCLIPath(_ path: String?, forProvider id: String) {
        store.write(value: path, key: "providers.\(id).cliPath")
    }

    /// `<id>.<setting>` — e.g. `claude.cliFallbackEnabled`, the key the Claude card writes.
    func isOn(_ setting: String, forProvider id: String) -> Bool? {
        store.read(key: "\(id).\(setting)")
    }

    func setOn(_ on: Bool, _ setting: String, forProvider id: String) {
        store.write(value: on, key: "\(id).\(setting)")
    }

    /// `<id>.<setting>` — e.g. `kimi.region`, the key the Kimi card writes.
    /// A value a provider's old card kept under another key is read from
    /// there, and moves the first time it is saved.
    func value(_ setting: String, forProvider id: String) -> String? {
        let key = "\(id).\(setting)"
        if let value = text(at: key) { return value }
        if let legacy = Self.legacySettingKeys[key], let value = text(at: legacy) { return value }
        return Self.legacyDefaultsKeys[key].flatMap { credentials.string(forKey: $0) }
    }

    func setValue(_ value: String?, _ setting: String, forProvider id: String) {
        let key = "\(id).\(setting)"
        store.write(value: value, key: key)
        if let legacy = Self.legacySettingKeys[key] { store.write(value: nil, key: legacy) }
        if let legacy = Self.legacyDefaultsKeys[key] { credentials.removeObject(forKey: legacy) }
    }

    /// A value as text — an old card may have saved a number, or a list
    /// (read as `a, b`).
    private func text(at key: String) -> String? {
        if let value: String = store.read(key: key) { return value }
        if let list: [String] = store.read(key: key) { return list.joined(separator: ", ") }
        if let number: NSNumber = store.read(key: key), CFGetTypeID(number) != CFBooleanGetTypeID() { return number.stringValue }
        return nil
    }

    /// Settings a provider's card kept under a key that isn't `<id>.<setting>`.
    /// A migrating provider adds a row here, never a branch.
    private static let legacySettingKeys = [
        "vercel-gateway.authEnvVar": "vercel.authEnvVar",
    ]

    /// Settings a provider's card kept in UserDefaults; they move to
    /// settings.json the first time they are saved.
    private static let legacyDefaultsKeys = [
        "copilot.username": "com.claudebar.credentials.github-username",
    ]

    func setEnabled(_ enabled: Bool, forProvider id: String) {
        store.write(value: enabled, key: "providers.\(id).isEnabled")
    }

    func customCardURL(forProvider id: String) -> String? {
        store.read(key: "providers.\(id).customCardURL")
    }

    func setCustomCardURL(_ url: String?, forProvider id: String) {
        let value: Any? = (url?.isEmpty == false) ? url : nil
        store.write(value: value, key: "providers.\(id).customCardURL")
    }

    func providerOrder() -> [String] {
        store.read(key: "providers.order") ?? []
    }

    /// An empty order removes the key, so the file keeps meaning "use the
    /// registration order" when nothing is stored — same rule as customCardURL.
    func setProviderOrder(_ order: [String]) {
        store.write(value: order.isEmpty ? nil : order, key: "providers.order")
    }

    func hiddenQuotaKeys(forProvider id: String) -> Set<String> {
        let stored: [String] = store.read(key: "providers.\(id).hiddenQuotaKeys") ?? []
        return Set(stored)
    }

    func setHiddenQuotaKeys(_ keys: Set<String>, forProvider id: String) {
        // Persist an empty set as a removal so the file stays free of empty
        // arrays and a fresh install reads back as "nothing hidden".
        let value: [String]? = keys.isEmpty ? nil : keys.sorted()
        store.write(value: value, key: "providers.\(id).hiddenQuotaKeys")
    }

    // MARK: - QuotaAlertSettingsRepository

    func quotaAlertPercents() -> [Int] {
        store.read(key: "alerts.thresholds") ?? []
    }

    func setQuotaAlertPercents(_ percents: [Int]) {
        store.write(value: percents, key: "alerts.thresholds")
    }

    // MARK: - WebhookSettingsRepository

    /// `alerts.webhooks`: everything but the URL, which is a secret, and the
    /// host and last delivery, which aren't saved. A row with a channel this
    /// version doesn't know is skipped. A row saved before the recap or the
    /// signed-out kind existed reads as sending neither.
    func webhooks() -> [Webhook] {
        let rows: [[String: Any]] = store.read(key: "alerts.webhooks") ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let channel = (row["channel"] as? String).flatMap(WebhookChannel.init(rawValue:)) else { return nil }
            return Webhook(
                id: id,
                name: row["name"] as? String ?? "",
                channel: channel,
                scope: (row["provider"] as? String).map(Webhook.Scope.provider) ?? .everyLogin,
                sends: Webhook.Sends(quotaAlerts: row["quotaAlerts"] as? Bool ?? true,
                                     statusAlerts: row["statusAlerts"] as? Bool ?? false,
                                     recap: row["recap"] as? Bool ?? false,
                                     signedOutAlerts: row["signedOutAlerts"] as? Bool ?? false),
                isOn: row["isOn"] as? Bool ?? true
            )
        }
    }

    func setWebhooks(_ webhooks: [Webhook]) {
        let rows: [[String: Any]] = webhooks.map { webhook in
            let provider: Any = switch webhook.scope {
            case .everyLogin: NSNull()
            case .provider(let id): id
            }
            return ["id": webhook.id, "name": webhook.name, "channel": webhook.channel.rawValue, "provider": provider,
                    "quotaAlerts": webhook.sends.quotaAlerts, "statusAlerts": webhook.sends.statusAlerts,
                    "recap": webhook.sends.recap, "signedOutAlerts": webhook.sends.signedOutAlerts,
                    "isOn": webhook.isOn]
        }
        store.write(value: rows, key: "alerts.webhooks")
    }

    // MARK: - RecapSentRepository

    /// `alerts.recapSentAt`: when the last recap went out, as seconds since
    /// the reference date — the store speaks numbers and strings, never dates.
    /// Absent means no recap has gone out yet.
    func lastSent() -> Date? {
        (store.read(key: "alerts.recapSentAt") as Double?).map(Date.init(timeIntervalSince1970:))
    }

    func setLastSent(_ date: Date) {
        store.write(value: date.timeIntervalSince1970, key: "alerts.recapSentAt")
    }

    // MARK: - HookSettingsRepository

    func isHookEnabled() -> Bool {
        store.read(key: "hook.enabled") ?? false
    }

    func setHookEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "hook.enabled")
    }

    func hookPort() -> Int {
        let port: Int = store.read(key: "hook.port") ?? Int(HookConstants.defaultPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    func setHookPort(_ port: Int) {
        store.write(value: port, key: "hook.port")
    }

    // MARK: - LocalAPISettingsRepository

    func isLocalAPIEnabled() -> Bool {
        store.read(key: "api.enabled") ?? false
    }

    func setLocalAPIEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "api.enabled")
    }

    // MARK: - NotifySettingsRepository

    func isNotifyEnabled() -> Bool {
        store.read(key: "notify.enabled") ?? NotifyConstants.defaultEnabled
    }

    func setNotifyEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.enabled")
    }

    func notifyDeviceId() -> String {
        store.read(key: "notify.deviceId") ?? ""
    }

    func setNotifyDeviceId(_ deviceId: String) {
        store.write(value: deviceId, key: "notify.deviceId")
    }

    // Notify! device token: a destination's secret, kept by `destinationSecrets`
    // (the Keychain, or the app credential store on a build the Keychain refuses).

    func saveNotifyDeviceToken(_ token: String) {
        // Tokens arrive pasted, so they arrive with stray whitespace. An empty
        // field is the user clearing the link rather than a request to store a
        // blank secret, which would look linked and then fail with a 403.
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteNotifyDeviceToken()
            return
        }
        destinationSecrets.save(trimmed, forKey: CredentialKey.notifyDeviceToken)
    }

    func notifyDeviceToken() -> String? {
        destinationSecrets.get(forKey: CredentialKey.notifyDeviceToken)
    }

    func notifyDeviceTokenIsSecure() -> Bool {
        destinationSecrets.isInKeychain(CredentialKey.notifyDeviceToken)
    }

    @discardableResult
    func deleteNotifyDeviceToken() -> Bool {
        destinationSecrets.delete(forKey: CredentialKey.notifyDeviceToken)
    }

    func hasNotifyDeviceToken() -> Bool {
        notifyDeviceToken() != nil
    }

    func isNotifyLiveActivityEnabled() -> Bool {
        store.read(key: "notify.liveActivityEnabled") ?? NotifyConstants.defaultLiveActivityEnabled
    }

    func setNotifyLiveActivityEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.liveActivityEnabled")
    }

    func isNotifyWidgetEnabled() -> Bool {
        store.read(key: "notify.widgetEnabled") ?? NotifyConstants.defaultWidgetEnabled
    }

    func setNotifyWidgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.widgetEnabled")
    }

    func isNotifyScreenWidgetEnabled() -> Bool {
        store.read(key: "notify.screenWidgetEnabled") ?? NotifyConstants.defaultScreenWidgetEnabled
    }

    func setNotifyScreenWidgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "notify.screenWidgetEnabled")
    }

    func notifyGaugeProviderId() -> String {
        store.read(key: "notify.gauge.providerId") ?? ""
    }

    func setNotifyGaugeProviderId(_ providerId: String) {
        store.write(value: providerId, key: "notify.gauge.providerId")
    }

    func notifyGaugeQuotaKey() -> String {
        store.read(key: "notify.gauge.quotaKey") ?? ""
    }

    func setNotifyGaugeQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "notify.gauge.quotaKey")
    }

    /// A word this version does not know falls back to the default rather than
    /// to nothing, so a settings file written by a newer ClaudeBar still
    /// arranges its row.
    func notifyTileOrder() -> NotifyTileOrder {
        guard let raw: String = store.read(key: "notify.tileOrder") else { return .worstFirst }
        return NotifyTileOrder(rawValue: raw) ?? .worstFirst
    }

    func setNotifyTileOrder(_ order: NotifyTileOrder) {
        store.write(value: order.rawValue, key: "notify.tileOrder")
    }

    func notifyActivityId() -> String? {
        store.read(key: "notify.activityId")
    }

    /// The optional is passed through untouched: `JSONSettingsStore.write` removes
    /// the key when the value is nil, and removal is exactly what forgetting a tile
    /// has to mean. A stored empty string would read back as a handle and send every
    /// later update to a tile that no longer exists.
    func setNotifyActivityId(_ activityId: String?) {
        store.write(value: activityId, key: "notify.activityId")
    }

    func notifyWidgetId() -> String? {
        store.read(key: "notify.widgetId")
    }

    /// Passed through for the same reason as the activity handle above.
    func setNotifyWidgetId(_ widgetId: String?) {
        store.write(value: widgetId, key: "notify.widgetId")
    }

    func notifyScreenWidgetId() -> String? {
        store.read(key: "notify.screenWidgetId")
    }

    /// Passed through for the same reason as the two handles above.
    func setNotifyScreenWidgetId(_ screenWidgetId: String?) {
        store.write(value: screenWidgetId, key: "notify.screenWidgetId")
    }

}

// MARK: - MultiAccountSettingsRepository

extension JSONSettingsRepository: MultiAccountSettingsRepository {

    func accounts(forProvider id: String) -> [ProviderAccountConfig] {
        guard let raw: [Any] = store.read(key: Self.accountsKey(id)) else { return [] }
        return raw.compactMap(Self.decodeAccount).map { Self.renamingValues(of: $0, forProvider: id) }
    }

    /// Values an added account kept under its definition's own name before
    /// a checked folder's became `folder` and its signed-in id `accountId`
    /// (#577). A migrating provider adds a row here, never a branch; the
    /// next save writes the new names.
    private static let renamedAccountValues = [
        "codex": ["codexHome": "folder", "chatgptAccountId": "accountId"],
        "claude": ["configDirectory": "folder", "loginEmail": "accountId"],
    ]

    private static func renamingValues(of config: ProviderAccountConfig, forProvider id: String) -> ProviderAccountConfig {
        guard let renames = renamedAccountValues[id] else { return config }
        var values = config.probeConfig
        for (old, new) in renames {
            if let value = values.removeValue(forKey: old), values[new] == nil { values[new] = value }
        }
        guard values != config.probeConfig else { return config }
        return ProviderAccountConfig(accountId: config.accountId, label: config.label, email: config.email,
                                     organization: config.organization, probeConfig: values, madeBy: config.madeBy)
    }

    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var configs = accounts(forProvider: id)
        if let index = configs.firstIndex(where: { $0.accountId == config.accountId }) {
            configs[index] = config
        } else {
            configs.append(config)
        }
        writeAccounts(configs, forProvider: id)
    }

    func removeAccount(accountId: String, forProvider id: String) {
        let remaining = accounts(forProvider: id).filter { $0.accountId != accountId }
        writeAccounts(remaining, forProvider: id)
    }

    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {
        var configs = accounts(forProvider: id)
        guard let index = configs.firstIndex(where: { $0.accountId == config.accountId }) else { return }
        configs[index] = config
        writeAccounts(configs, forProvider: id)
    }

    func defaultAccountLabel(forProvider id: String) -> String? {
        store.read(key: Self.defaultAccountLabelKey(id))
    }

    func setDefaultAccountLabel(_ label: String?, forProvider id: String) {
        store.write(value: label, key: Self.defaultAccountLabelKey(id))
    }

    // MARK: Storage helpers

    private static func accountsKey(_ id: String) -> String { "providers.\(id).accounts" }
    func accountOrder(forProvider id: String) -> [String] {
        store.read(key: Self.accountOrderKey(id)) ?? []
    }

    func setAccountOrder(_ accountIds: [String], forProvider id: String) {
        store.write(value: accountIds.isEmpty ? nil : accountIds, key: Self.accountOrderKey(id))
    }

    private static func defaultAccountLabelKey(_ id: String) -> String { "providers.\(id).defaultAccountLabel" }
    private static func accountOrderKey(_ id: String) -> String { "providers.\(id).accountOrder" }

    private func writeAccounts(_ configs: [ProviderAccountConfig], forProvider id: String) {
        // Persist an empty list as a removal so the file stays free of empty arrays,
        // which keeps `accounts(forProvider:)` on its single-account path.
        let value = configs.isEmpty ? nil : configs.compactMap(Self.encodeAccount)
        store.write(value: value, key: Self.accountsKey(id))
    }

    /// `JSONSettingsStore` persists via `JSONSerialization`, so configs travel as
    /// plain dictionaries rather than as `Codable` values.
    private static func encodeAccount(_ config: ProviderAccountConfig) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(config),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func decodeAccount(_ raw: Any) -> ProviderAccountConfig? {
        guard let object = raw as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: object),
              let config = try? JSONDecoder().decode(ProviderAccountConfig.self, from: data) else {
            return nil
        }
        return config
    }
}

// MARK: - LeaderboardSettingsRepository

// A destination's own namespace, `leaderboard.*`, beside `notify.*`. The
// private key is not here: the `Leaderboard` module's `SigningKeyStore` keeps it.
extension JSONSettingsRepository: LeaderboardSettingsRepository {
    /// The membership kept as `leaderboard.*`; `nil` when not joined.
    func leaderboardRecord() -> LeaderboardRecord? {
        guard let username: String = store.read(key: "leaderboard.username") else { return nil }
        let lastUpload: Double? = store.read(key: "leaderboard.lastUpload")
        return LeaderboardRecord(
            username: username,
            sharing: store.read(key: "leaderboard.sharing") ?? [],
            visible: store.read(key: "leaderboard.visible") ?? true,
            lastUpload: lastUpload.map(Date.init(timeIntervalSince1970:)),
            sharesCountry: store.read(key: "leaderboard.sharesCountry") ?? false,
            globeHintDismissed: store.read(key: "leaderboard.globeHintDismissed") ?? false,
            link: (store.read(key: "leaderboard.linkPlatform") as String?)
                .flatMap(ProfileLink.Platform.init(rawValue:))
                .flatMap { platform in (store.read(key: "leaderboard.linkHandle") as String?).flatMap { ProfileLink(platform: platform, handle: $0) } },
            refused: (store.read(key: "leaderboard.refused") as [[String: String]]? ?? []).compactMap { day in
                guard let provider = day["provider"], let date = day["day"], let reason = day["reason"] else { return nil }
                return RefusedDay(provider: provider, day: date, reason: reason)
            },
            shownDevices: store.read(key: "leaderboard.shownDevices") ?? [],
            machine: store.read(key: "leaderboard.machine"),
            addedAsDevice: store.read(key: "leaderboard.addedAsDevice") ?? false,
            // `{provider: {day: total}}`; absent for a record from before it was kept.
            sent: (store.read(key: "leaderboard.sent") as [String: [String: Int]]?).map { providers in
                providers.flatMap { provider, days in days.map { SentDay(provider: provider, day: $0.key, total: $0.value) } }
            },
            heldBefore: store.read(key: "leaderboard.heldBefore")
        )
    }

    func isLeaderboardOn() -> Bool {
        store.read(key: "leaderboard.on") ?? true
    }

    func setLeaderboardOn(_ on: Bool) {
        store.write(value: on, key: "leaderboard.on")
    }

    /// Writes the membership as `leaderboard.*`; `nil` removes every key of it.
    func saveLeaderboardRecord(_ record: LeaderboardRecord?) {
        store.write(value: record?.username, key: "leaderboard.username")
        store.write(value: record?.sharing, key: "leaderboard.sharing")
        store.write(value: record?.visible, key: "leaderboard.visible")
        store.write(value: record?.lastUpload?.timeIntervalSince1970, key: "leaderboard.lastUpload")
        store.write(value: record?.sharesCountry, key: "leaderboard.sharesCountry")
        store.write(value: record?.globeHintDismissed, key: "leaderboard.globeHintDismissed")
        store.write(value: record?.link?.platform.rawValue, key: "leaderboard.linkPlatform")
        store.write(value: record?.link?.handle, key: "leaderboard.linkHandle")
        let refused = record?.refused.map { ["provider": $0.provider, "day": $0.day, "reason": $0.reason] }
        store.write(value: refused?.isEmpty == false ? refused : nil, key: "leaderboard.refused")
        store.write(value: record?.shownDevices.isEmpty == false ? record?.shownDevices : nil, key: "leaderboard.shownDevices")
        store.write(value: record?.machine, key: "leaderboard.machine")
        store.write(value: record?.addedAsDevice == true ? true : nil, key: "leaderboard.addedAsDevice")
        // Written even when empty: a record without it is one from before it was kept.
        let sent = record?.sent.map { days in
            Dictionary(grouping: days, by: \.provider).mapValues { Dictionary($0.map { ($0.day, $0.total) }, uniquingKeysWith: max) }
        }
        store.write(value: sent, key: "leaderboard.sent")
        store.write(value: record?.heldBefore, key: "leaderboard.heldBefore")
    }
}

// MARK: - RestWhenEmptyRepository

// `providers.<id>.restWhenEmpty`: one object per product, absent while the
// person never asked. A state this version doesn't know reads as not asked.
extension JSONSettingsRepository: RestWhenEmptyRepository {
    func whenEmpty(forProvider id: String) -> WhenEmpty? {
        guard let saved: [String: Any] = store.read(key: Self.restWhenEmptyKey(id)) else { return nil }
        switch saved["state"] as? String {
        case "watching": return .watching
        case "shownAnyway": return .shownAnyway
        case "resting":
            let since = (saved["since"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            return .resting(since: since)
        default: return nil
        }
    }

    func setWhenEmpty(_ state: WhenEmpty?, forProvider id: String) {
        let saved: [String: Any]? = switch state {
        case nil: nil
        case .watching: ["state": "watching"]
        case .shownAnyway: ["state": "shownAnyway"]
        case let .resting(since): ["state": "resting", "since": since.timeIntervalSince1970]
        }
        store.write(value: saved, key: Self.restWhenEmptyKey(id))
    }

    private static func restWhenEmptyKey(_ id: String) -> String { "providers.\(id).restWhenEmpty" }
}
