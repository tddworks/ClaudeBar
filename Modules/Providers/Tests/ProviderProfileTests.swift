import Foundation
import Providers
import Testing

/// WHO IT IS — a built-in provider's name, links and face come from its
/// definition, with the exact values the `switch id` tables used to hold.
@Suite
struct ProviderProfileTests {
    @Test
    func `claude's profile is its name, links and face`() throws {
        let profile = try Providers.builtIn("claude").profile

        #expect(profile.id == "claude")
        #expect(profile.name == "Claude")
        #expect(profile.origin == .builtIn)
        #expect(profile.look.symbol == "brain.fill")
        #expect(profile.look.icon == "ClaudeIcon")
        #expect(profile.look.color == .init(light: .init(0.95, 0.48, 0.38), dark: .init(0.98, 0.55, 0.45)))
        #expect(profile.look.gradientEnd == .init(light: .init(0.92, 0.45, 0.72), dark: .init(0.85, 0.35, 0.65)))
        #expect(profile.links.status == URL(string: "https://status.anthropic.com"))
    }

    @Test
    func `codex's profile is its name, links and face`() throws {
        let profile = try Providers.builtIn("codex").profile

        #expect(profile.name == "Codex")
        #expect(profile.look.symbol == "chevron.left.forwardslash.chevron.right")
        #expect(profile.look.icon == "CodexIcon")
        #expect(profile.look.color == .init(light: .init(0.18, 0.72, 0.68), dark: .init(0.35, 0.85, 0.78)))
        #expect(profile.look.gradientEnd == .init(light: .init(0.12, 0.52, 0.72), dark: .init(0.25, 0.65, 0.85)))
    }

    @Test
    func `an added login's id finds its product's definition`() {
        #expect(Providers.builtInDefinition(forLineupId: "codex.4f2a")?.id == "codex")
        #expect(Providers.builtInDefinition(forLineupId: "claude")?.id == "claude")
        #expect(Providers.builtInDefinition(forLineupId: "acme-not-built-in") == nil)
    }

    @Test
    func `the origin is where the file came from, never what it says`() throws {
        let data = try Providers.builtInData("codex")

        #expect(try ProviderDefinition.parse(data, origin: .custom).profile.origin == .custom)
    }
}
