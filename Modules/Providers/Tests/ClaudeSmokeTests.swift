import Quotas
import Foundation
import Testing

@Suite
struct ClaudeSmokeTests {
    @Test
    func `should show the session, weekly and Opus windows with their resets when Claude prints a plain usage screen`() throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        let usage = try claude.readUsageScreen("""
        Claude Code v1.0.27

        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
        Resets Jan 15, 3:30pm (America/Los_Angeles)

        Current week (Opus)
        ████████████████████ 80% left
        """)

        #expect(usage.sessionQuota?.percentRemaining == 65)
        #expect(usage.sessionQuota?.resetText == "Resets in 2h 15m")
        #expect(usage.sessionQuota?.resetsAt != nil)
        #expect(usage.weeklyQuota?.percentRemaining == 35)
        #expect(usage.quota(for: .modelSpecific("opus"))?.percentRemaining == 80)
        #expect(usage.accountTier == .claudeMax)
    }

    @Test
    func `should show an over-limit session, the Max plan and extra-usage spend when Claude's usage API answers`() async throws {
        let claude = try ClaudeHarness()
        defer { claude.cleanUp() }

        let usage = try await claude.readAPIResponse(
            #"{"five_hour":{"utilization":105,"resets_at":"2099-01-01T00:00:00Z"},"extra_usage":{"is_enabled":true,"used_credits":1234,"monthly_limit":5000}}"#,
            subscriptionType: "claude_max"
        )

        #expect(usage.sessionQuota?.percentRemaining == -5)
        #expect(usage.accountTier == .claudeMax)
        #expect(usage.costUsage?.totalCost == Decimal(string: "12.34"))
        #expect(usage.costUsage?.budget == 50)
    }
}
