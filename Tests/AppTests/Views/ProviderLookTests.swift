import SwiftUI
import Testing
@testable import ClaudeBar

/// The faces of Claude and Codex now come from their definitions; these are
/// the exact colours, symbols, icons and names the old `switch id` tables gave.
@Suite @MainActor
struct ProviderLookTests {
    @Test func `claude keeps its colours`() {
        #expect(ProviderVisualIdentityLookup.color(for: "claude", scheme: .dark) == BaseTheme.coralAccent)
        #expect(ProviderVisualIdentityLookup.color(for: "claude", scheme: .light) == Color(red: 0.95, green: 0.48, blue: 0.38))
    }

    @Test func `codex keeps its colours, for every login`() {
        #expect(ProviderVisualIdentityLookup.color(for: "codex", scheme: .dark) == BaseTheme.tealBright)
        #expect(ProviderVisualIdentityLookup.color(for: "codex.work", scheme: .light) == Color(red: 0.18, green: 0.72, blue: 0.68))
    }

    @Test func `symbols, icons and names come from the profile`() {
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "claude") == "brain.fill")
        #expect(ProviderVisualIdentityLookup.iconAssetName(for: "claude") == "ClaudeIcon")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "codex.work") == "chevron.left.forwardslash.chevron.right")
        #expect(ProviderVisualIdentityLookup.name(for: "codex") == "Codex")
    }
}
