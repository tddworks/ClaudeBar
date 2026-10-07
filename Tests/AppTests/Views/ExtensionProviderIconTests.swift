import Foundation
import Testing
@testable import ClaudeBar
import Kit

/// An extension's icon is the SF Symbol its manifest names (#302), now read
/// through its definition (docs/features/extensions/design.md) — and a symbol that doesn't exist
/// keeps the question mark.
@MainActor
@Suite(.serialized)
struct ExtensionProviderIconTests {
    /// A kit holding one extension whose manifest names `icon`.
    private func register(id: String, icon: String?) throws -> ClaudeBarCore {
        let iconField = icon.map { #","icon":"\#($0)""# } ?? ""
        return try TestKit.start(extensions: [id: """
        {"id":"\(id)","name":"Icon","version":"1"\(iconField),
         "sections":[{"id":"quotas","type":"quotaGrid","probe":{"command":"./probe.sh"}}]}
        """])
    }

    @Test
    func `should show an extension with the SF Symbol its manifest names (#302)`() throws {
        let kit = try register(id: "icon-atom", icon: "atom")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-atom", in: kit) == "atom")
    }

    @Test
    func `should show a question mark for an extension that names no icon`() throws {
        let kit = try register(id: "icon-none", icon: nil)
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-none", in: kit) == "questionmark.circle.fill")
    }

    @Test
    func `should show a question mark for an extension whose icon doesn't exist`() throws {
        let kit = try register(id: "icon-bogus", icon: "not.a.real.symbol.name")
        #expect(ProviderVisualIdentityLookup.symbolIcon(for: "ext-icon-bogus", in: kit) == "questionmark.circle.fill")
    }
}
