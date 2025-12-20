import Testing
import Foundation
@testable import Domain

@Suite("Usage Quota Tests")
struct UsageQuotaTests {

    // MARK: - Quota Creation

    @Test("Creates usage quota with percentage remaining")
    func createQuotaWithPercentage() {
        let quota = UsageQuota(
            percentRemaining: 65,
            quotaType: .session,
            provider: .claude
        )

        #expect(quota.percentRemaining == 65)
        #expect(quota.quotaType == .session)
        #expect(quota.provider == .claude)
    }

    @Test("Creates usage quota with reset time")
    func createQuotaWithResetTime() {
        let resetDate = Date().addingTimeInterval(3600) // 1 hour from now
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            provider: .claude,
            resetsAt: resetDate
        )

        #expect(quota.resetsAt == resetDate)
        #expect(quota.quotaType == .weekly)
    }

    // MARK: - Quota Types

    @Test("Session quota type has correct properties")
    func sessionQuotaType() {
        let quotaType = QuotaType.session

        #expect(quotaType.displayName == "Current Session")
        #expect(quotaType.duration == .hours(5))
    }

    @Test("Weekly quota type has correct properties")
    func weeklyQuotaType() {
        let quotaType = QuotaType.weekly

        #expect(quotaType.displayName == "Weekly")
        #expect(quotaType.duration == .days(7))
    }

    @Test("Model-specific quota type has correct properties")
    func modelSpecificQuotaType() {
        let quotaType = QuotaType.modelSpecific("opus")

        #expect(quotaType.displayName == "Opus")
        #expect(quotaType.modelName == "opus")
    }

    // MARK: - Quota Status

    @Test("Quota is healthy when above 50%")
    func quotaHealthyAbove50() {
        let quota = UsageQuota(
            percentRemaining: 65,
            quotaType: .session,
            provider: .claude
        )

        #expect(quota.status == .healthy)
    }

    @Test("Quota is warning when between 20-50%")
    func quotaWarningBetween20And50() {
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .session,
            provider: .claude
        )

        #expect(quota.status == .warning)
    }

    @Test("Quota is critical when below 20%")
    func quotaCriticalBelow20() {
        let quota = UsageQuota(
            percentRemaining: 15,
            quotaType: .session,
            provider: .claude
        )

        #expect(quota.status == .critical)
    }

    @Test("Quota is depleted when at 0%")
    func quotaDepletedAtZero() {
        let quota = UsageQuota(
            percentRemaining: 0,
            quotaType: .session,
            provider: .claude
        )

        #expect(quota.status == .depleted)
    }

    // MARK: - Quota Comparisons

    @Test("Quotas are comparable by percentage")
    func quotasComparableByPercentage() {
        let highQuota = UsageQuota(percentRemaining: 80, quotaType: .session, provider: .claude)
        let lowQuota = UsageQuota(percentRemaining: 20, quotaType: .session, provider: .claude)

        #expect(highQuota > lowQuota)
        #expect(lowQuota < highQuota)
    }

    @Test("Equal quotas are equal")
    func equalQuotasAreEqual() {
        let quota1 = UsageQuota(percentRemaining: 50, quotaType: .session, provider: .claude)
        let quota2 = UsageQuota(percentRemaining: 50, quotaType: .session, provider: .claude)

        #expect(quota1 == quota2)
    }
}
