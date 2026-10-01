import Testing
import Foundation
import Domain
@testable import ClaudeBar

@Suite @MainActor
struct ExtensionProviderIconTests {
    private func manifest(id: String, icon: String?) -> ExtensionManifest {
        ExtensionManifest(id: id, name: id.capitalized, version: "1.0.0", icon: icon, sections: [])
    }

    private func provider(id: String, icon: String?) -> ExtensionProvider {
        ExtensionProvider(
            manifest: manifest(id: id, icon: icon),
            probes: [:],
            settingsRepository: InMemoryProviderSettings()
        )
    }

    @Test
    func `extension provider uses the SF Symbol its manifest declares`() {
        ProviderVisualIdentityLookup.registerExtensionIcons(from: [provider(id: "icon-atom", icon: "atom")])

        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-atom") == "atom")
    }

    @Test
    func `extension provider without an icon keeps the question mark`() {
        ProviderVisualIdentityLookup.registerExtensionIcons(from: [provider(id: "icon-none", icon: nil)])

        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-none") == "questionmark.circle.fill")
    }

    @Test
    func `extension provider with an unknown symbol name keeps the question mark`() {
        ProviderVisualIdentityLookup.registerExtensionIcons(from: [
            provider(id: "icon-bogus", icon: "not.a.real.symbol.claudebar"),
            provider(id: "icon-empty", icon: ""),
        ])

        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-bogus") == "questionmark.circle.fill")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-empty") == "questionmark.circle.fill")
    }

    @Test
    func `extension icon cannot replace a built-in provider icon`() {
        ProviderVisualIdentityLookup.registerExtensionIcons(from: [provider(id: "claude", icon: "atom")])

        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "claude") == "brain.fill")
        #expect(ProviderVisualIdentityLookup.iconAssetName(for: "claude") == "ClaudeIcon")
    }

    @Test
    func `extension provider object exposes its manifest icon`() {
        #expect(provider(id: "icon-object", icon: "atom").symbolIconOrDefault == "atom")
    }
}

private final class InMemoryProviderSettings: ProviderSettingsRepository, @unchecked Sendable {
    private var enabled: [String: Bool] = [:]
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { enabled[id] ?? defaultValue }
    func isEnabled(forProvider id: String) -> Bool { enabled[id] ?? true }
    func setEnabled(_ enabled: Bool, forProvider id: String) { self.enabled[id] = enabled }
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
}
