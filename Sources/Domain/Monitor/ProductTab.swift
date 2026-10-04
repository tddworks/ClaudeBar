import Foundation
import Providers

/// A pill in the popover: one product, with every enabled login of it — so
/// three Claude logins are one *Claude* tab, side by side, not three tabs.
/// Its logins come in the order the person gave them.
@MainActor
public struct ProductTab: Identifiable {
    /// The product's id — `codex`, never `codex.<acct>`.
    public let id: String
    public let name: String
    /// Its logins in the lineup, in the person's order.
    public let accounts: [any AIProvider]

    /// The product behind a tab of logins; `nil` for a legacy provider.
    public var provider: Provider? { (accounts.first as? Account)?.provider }

    public func contains(_ lineupId: String) -> Bool {
        accounts.contains { $0.id == lineupId }
    }

    /// The lineup as tabs, in the order products first appear in it.
    public static func tabs(of lineup: [any AIProvider]) -> [ProductTab] {
        var tabs: [ProductTab] = []
        var seen: Set<String> = []
        for member in lineup {
            guard let account = member as? Account else {
                tabs.append(ProductTab(id: member.id, name: member.name, accounts: [member]))
                continue
            }
            let product = account.provider
            guard seen.insert(product.id).inserted else { continue }
            let shown = Set(lineup.map(\.id))
            let accounts: [any AIProvider] = product.accounts.filter { shown.contains($0.id) }
            tabs.append(ProductTab(id: product.id, name: product.name, accounts: accounts))
        }
        return tabs
    }
}
