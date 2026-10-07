import Foundation
@testable import Domain

/// A product for tests about the Monitor, the lineup and selection: a real
/// `Provider` from a one-source definition, its connection stubbed to answer
/// with whatever `probe` says (TARGET §7 — "the test stubs become
/// definitions over stubbed connections"). Only the identity matters here;
/// each real provider is tested end to end in `ProvidersTests`.
@MainActor
func stubbedProduct(_ id: String, name: String? = nil, probe: any UsageProbe,
               settings: any ProviderSettingsRepository, available: Bool = true,
               backgroundRefreshFloor: Duration? = nil) -> Provider {
    // A data source with a cache sets the background floor, as Claude's API does.
    let cache = backgroundRefreshFloor.map { #","cache":{"ttl":\#($0.components.seconds)}"# } ?? ""
    let json = """
    {"profile":{"id":"\(id)","name":"\(name ?? id.prefix(1).uppercased() + id.dropFirst())","links":{}},
     "dataSources":[{"kind":"stub","credential":{"environment":"STUB_READY"},
                     "fetch":{"http":{"url":"https://stub.invalid/\(id)"}},"mapping":{"usage":{}}\(cache)}],
     "defaultDataSource":"stub"}
    """
    let definition = try! ProviderDefinition.parse(Data(json.utf8), origin: .custom)
    let network = ProbeAnswers(probe: probe)
    let provider = Provider(definition: definition, settings: LegacySettings(settings), makeDataSource: { source, _ in
        DataSources.make(source, providerId: id, cliExecutor: NoCLI(), network: network,
                         makeTransport: { _, _, _, _ in throw UsageError.executionFailed("no RPC in a stub") },
                         environment: { $0 == "STUB_READY" && available ? "ready" : nil },
                         homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
    })
    return provider
}

/// The providers a test keeps, in order.
@MainActor
func kept(_ products: [Provider], settings: (any ProviderSettingsRepository)? = nil) -> Providers {
    Providers(products, settings: settings, make: { _ in fatalError("tests don't add providers") })
}

/// The stubbed connection: answers each request with the probe's usage, as
/// ClaudeBar's own usage JSON (`Mapping.usage`).
private struct ProbeAnswers: NetworkClient {
    let probe: any UsageProbe

    func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let usage = try await probe.probe()
        let formatter = ISO8601DateFormatter()
        var output: [String: Any] = ["quotas": usage.quotas.map { quota -> [String: Any] in
            var entry: [String: Any] = ["type": Self.type(quota.quotaType), "percentRemaining": quota.percentRemaining]
            if let resetsAt = quota.resetsAt { entry["resetsAt"] = formatter.string(from: resetsAt) }
            if let resetText = quota.resetText { entry["resetText"] = resetText }
            if let dollars = quota.dollarRemaining { entry["dollarRemaining"] = NSDecimalNumber(decimal: dollars).doubleValue }
            return entry
        }]
        if let cost = usage.costUsage {
            output["costUsage"] = ["totalCost": NSDecimalNumber(decimal: cost.totalCost).doubleValue,
                                   "apiDuration": cost.apiDuration]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (try JSONSerialization.data(withJSONObject: output), response)
    }

    private static func type(_ kind: QuotaType) -> String {
        switch kind.shape {
        case .session: "session"
        case .weekly: "weekly"
        case .modelSpecific(let model): "model:\(model)"
        case .timeLimit(let name): name
        }
    }
}

private struct NoCLI: CLIExecutor {
    func locate(_ binary: String) -> String? { nil }
    func execute(binary: String, args: [String], input: String?, timeout: TimeInterval,
                 workingDirectory: URL?, autoResponses: [String: String]) async throws -> CLIResult {
        throw UsageError.cliNotFound(binary)
    }
}

/// A test's settings as a provider reads them: whether it is on comes from
/// the test's repository, as it did for the old stubs; the rest is kept here.
private final class LegacySettings: MultiAccountSettingsRepository, @unchecked Sendable {
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
