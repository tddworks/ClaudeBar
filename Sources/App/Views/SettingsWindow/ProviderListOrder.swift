import Foundation

/// The order of Settings → Providers: the providers a person turned on first,
/// then the rest, each group in its usual order (#141). Taken when the list
/// appears and kept while it is open, so a row never jumps under the switch
/// being flipped.
enum ProviderListOrder {
    /// Enabled ids first, then disabled, each group in the order given.
    static func listed(_ providers: [(id: String, isEnabled: Bool)]) -> [String] {
        providers.filter(\.isEnabled).map(\.id) + providers.filter { !$0.isEnabled }.map(\.id)
    }

    /// An order taken earlier, still standing: providers that went away
    /// leave it, and providers added since join the end.
    static func keeping(_ order: [String], current: [String]) -> [String] {
        let present = Set(current)
        let kept = order.filter(present.contains)
        return kept + current.filter { !kept.contains($0) }
    }
}
