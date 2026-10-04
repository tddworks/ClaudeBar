import DataSources
import Quotas
import Foundation
import Mockable
import Providers
import Testing

/// #328: the Dashboard opens claude.ai usage settings for a subscription, and
/// Console billing for an API account — `claude.json`'s `dashboardByPlan`.
@MainActor
@Suite
struct ClaudeDashboardTests {
    static let subscriptionUsageURL = URL(string: "https://claude.ai/new#settings/usage")
    static let consoleBillingURL = URL(string: "https://console.anthropic.com/settings/billing")

    /// `screen` is what `/usage` shows; `/cost`, when `/usage` hands off to it, shows `cost`.
    private func claude(afterReading screen: String, cost: String = "") async throws -> Account {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        given(claude.cli).locate(.any).willReturn("/usr/local/bin/claude")
        given(claude.cli).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { @Sendable _, args, _, _, _, _ in
                CLIResult(output: args.contains("/cost") ? cost : screen)
            }
        let provider = try claude.provider()
        try await provider.refresh()
        return provider
    }

    @Test
    func `dashboard opens claude.ai usage settings for a Max account`() async throws {
        let provider = try await claude(afterReading: "Opus 4.7 · Claude Max\nCurrent session\n████ 65% left")
        #expect(provider.snapshot?.accountTier == .claudeMax)
        #expect(provider.dashboardURL == Self.subscriptionUsageURL)
    }

    @Test
    func `dashboard opens claude.ai usage settings for a Pro account`() async throws {
        let provider = try await claude(afterReading: "Sonnet 4.6 · Claude Pro\nCurrent session\n████ 65% left")
        #expect(provider.snapshot?.accountTier == .claudePro)
        #expect(provider.dashboardURL == Self.subscriptionUsageURL)
    }

    @Test
    func `dashboard opens Console billing for an API account`() async throws {
        let provider = try await claude(
            afterReading: "/usage is only available for subscription plans.",
            cost: "Total cost:            $1.23\nTotal duration (API):  1m 30s"
        )
        #expect(provider.snapshot?.accountTier == .claudeApi)
        #expect(provider.dashboardURL == Self.consoleBillingURL)
    }

    @Test
    func `dashboard opens claude.ai usage settings for other plans and before the first refresh`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }
        let definition = try Providers.builtIn("claude")

        #expect(try claude.provider().dashboardURL == Self.subscriptionUsageURL)
        #expect(definition.profile.links.dashboard(for: .custom("Enterprise")) == Self.subscriptionUsageURL)
        #expect(definition.profile.links.dashboard(for: nil) == Self.subscriptionUsageURL)
    }
}
