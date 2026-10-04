import DataSources
import Foundation
import Providers

/// The words of Settings' *Data source* section, all read from a provider's
/// definition — so a provider that is data needs no card of its own (#352).
struct DataSourceSectionText {
    struct Choice: Equatable {
        let kind: String
        let label: String
        let summary: String?
    }

    let definition: ProviderDefinition

    var title: String { "\(definition.profile.name) Configuration" }

    var subtitle: String {
        definition.accounts == nil
            ? "Data fetching method"
            : "Data fetching method for all \(definition.profile.name) accounts"
    }

    /// The badge — *Built in · Custom · Extension*.
    var origin: String {
        switch definition.profile.origin {
        case .builtIn: "Built in"
        case .custom: "Custom"
        case .extension: "Extension"
        }
    }

    /// *CLI LOCATION* — for a provider that runs a CLI: what it finds on its
    /// own, and where the chosen program is used (#210).
    var cliLocation: (placeholder: String, help: String)? {
        definition.cli.map { cli in
            ("Found automatically: \(cli)",
             "The \(cli) program ClaudeBar runs for every account and for Add Account's sign-in. Choose one when yours isn't found, or isn't the one you want. A shell alias can't be used: choose the program it runs.")
        }
    }

    /// The data sources a person can pick — not the ones only a fallback reaches.
    var choices: [Choice] {
        definition.dataSources.filter { !$0.hidden }.map {
            Choice(kind: $0.kind, label: label(of: $0.kind), summary: $0.summary)
        }
    }

    /// *KEY LOOKUP ORDER* — `nil` for a data source that needs no key.
    func lookupOrder(for kind: String) -> String? {
        guard let lookup = definition.dataSource(kind)?.credential else { return nil }
        return lookup.lookupOrder.joined(separator: " → ")
    }

    /// What to do when no key answers.
    func keyHint(for kind: String) -> String? {
        definition.dataSource(kind)?.credential?.hint
    }

    func note(for kind: String) -> String? {
        definition.dataSource(kind)?.note
    }

    /// The fallback as one sentence — "If API is unavailable, ClaudeBar tries CLI."
    func fallback(for kind: String) -> String? {
        guard let fallback = definition.dataSource(kind)?.fallback else { return nil }
        return "If \(label(of: kind)) is unavailable, ClaudeBar tries \(label(of: fallback.to))."
    }

    /// Whether the person can switch the fallback off.
    func fallbackIsSwitchable(for kind: String) -> Bool {
        definition.dataSource(kind)?.fallback?.enabledBySetting != nil
    }

    /// A cached data source caps the background refresh (#204).
    func cacheNote(for kind: String) -> String? {
        guard let ttl = definition.dataSource(kind)?.cache?.ttl else { return nil }
        let minutes = Int(ttl / 60)
        return "Usage data is cached for \(minutes) min, so background refresh is capped at \(minutes) min while \(label(of: kind)) is in use."
    }

    static func testResult(_ result: Result<Response, DataSourceError>) -> String {
        switch result {
        case .success(let response):
            response.status.map { "Connected · \($0)" } ?? "Connected"
        case .failure(let error):
            "\(RefreshReport.headline(for: error.step)) · \(error.reason.localizedDescription)"
        }
    }

    private func label(of kind: String) -> String {
        definition.dataSource(kind)?.label ?? kind
    }
}
