import Foundation
@testable import Domain

/// A test's settings as a provider reads them: whether it is on comes from
/// the test's repository, as it did for the old stubs; the rest is kept here.
final class LegacySettings: MultiAccountSettingsRepository, @unchecked Sendable {
    private let wrapped: any ProviderSettingsRepository
    private var flags: [String: Bool] = [:]
    private var values: [String: String] = [:]

    init(_ wrapped: any ProviderSettingsRepository) { self.wrapped = wrapped }

    func isEnabled(forProvider id: String) -> Bool { wrapped.isEnabled(forProvider: id) }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { wrapped.isEnabled(forProvider: id) }
    func setEnabled(_ enabled: Bool, forProvider id: String) { wrapped.setEnabled(enabled, forProvider: id) }
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func isOn(_ setting: String, forProvider id: String) -> Bool? { flags["\(id).\(setting)"] }
    func setOn(_ on: Bool, _ setting: String, forProvider id: String) { flags["\(id).\(setting)"] = on }
    func value(_ setting: String, forProvider id: String) -> String? { values["\(id).\(setting)"] }
    func setValue(_ value: String?, _ setting: String, forProvider id: String) { values["\(id).\(setting)"] = value }
    func accounts(forProvider id: String) -> [ProviderAccountConfig] { [] }
    func addAccount(_ config: ProviderAccountConfig, forProvider id: String) {}
    func removeAccount(accountId: String, forProvider id: String) {}
    func updateAccount(_ config: ProviderAccountConfig, forProvider id: String) {}
    func defaultAccountLabel(forProvider id: String) -> String? { nil }
    func setDefaultAccountLabel(_ label: String?, forProvider id: String) {}
    func accountOrder(forProvider id: String) -> [String] { [] }
    func setAccountOrder(_ accountIds: [String], forProvider id: String) {}
}
