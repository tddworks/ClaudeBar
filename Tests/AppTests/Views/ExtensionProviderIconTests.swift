import Foundation
import Testing
@testable import ClaudeBar
import Domain

/// An extension's icon is the SF Symbol its manifest names (#302), now read
/// through its definition (docs/features/providers/extensions/design.md) — and a symbol that doesn't exist
/// keeps the question mark.
@MainActor
@Suite(.serialized)
struct ExtensionProviderIconTests {
    private func register(id: String, icon: String?) throws {
        let iconField = icon.map { #","icon":"\#($0)""# } ?? ""
        let definition = try Extensions.definition(manifest: Data("""
        {"id":"\(id)","name":"Icon","version":"1"\(iconField),
         "sections":[{"id":"quotas","type":"quotaGrid","probe":{"command":"./probe.sh"}}]}
        """.utf8), folder: FileManager.default.temporaryDirectory)
        ProviderFactory.register(custom: definition)
    }

    @Test
    func `should show an extension with the SF Symbol its manifest names (#302)`() throws {
        try register(id: "icon-atom", icon: "atom")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-atom") == "atom")
    }

    @Test
    func `should show a question mark for an extension that names no icon`() throws {
        try register(id: "icon-none", icon: nil)
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-none") == "questionmark.circle.fill")
    }

    @Test
    func `should show a question mark for an extension whose icon doesn't exist`() throws {
        try register(id: "icon-bogus", icon: "not.a.real.symbol.name")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-bogus") == "questionmark.circle.fill")
    }
}
