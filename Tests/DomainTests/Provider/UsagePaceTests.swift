import Testing
import Foundation
@testable import Domain

@Suite
struct UsagePaceTests {

    // MARK: - Factory Method

    @Test
    func `on pace when usage matches time elapsed within threshold`() {
        // Given: 50% time elapsed, 52% used (within 5% threshold)
        let pace = UsagePace.from(percentUsed: 52, percentTimeElapsed: 50)

        // Then
        #expect(pace == .onPace)
    }

    @Test
    func `on pace when usage exactly matches time elapsed`() {
        let pace = UsagePace.from(percentUsed: 50, percentTimeElapsed: 50)
        #expect(pace == .onPace)
    }

    @Test
    func `on pace at threshold boundary`() {
        // Exactly 5% difference should still be on pace
        let pace = UsagePace.from(percentUsed: 55, percentTimeElapsed: 50)
        #expect(pace == .onPace)
    }

    @Test
    func `ahead when consuming faster than expected`() {
        // Given: 30% time elapsed, 50% used
        let pace = UsagePace.from(percentUsed: 50, percentTimeElapsed: 30)

        // Then
        #expect(pace == .ahead)
    }

    @Test
    func `behind when consuming slower than expected`() {
        // Given: 50% time elapsed, 30% used
        let pace = UsagePace.from(percentUsed: 30, percentTimeElapsed: 50)

        // Then
        #expect(pace == .behind)
    }

    @Test
    func `ahead just beyond threshold`() {
        // 5.1% difference (just beyond 5% threshold)
        let pace = UsagePace.from(percentUsed: 55.1, percentTimeElapsed: 50)
        #expect(pace == .ahead)
    }

    @Test
    func `behind just beyond threshold`() {
        // -5.1% difference (just beyond 5% threshold)
        let pace = UsagePace.from(percentUsed: 44.9, percentTimeElapsed: 50)
        #expect(pace == .behind)
    }

    @Test
    func `ahead when fully used early in period`() {
        // Given: 10% time elapsed, 100% used
        let pace = UsagePace.from(percentUsed: 100, percentTimeElapsed: 10)
        #expect(pace == .ahead)
    }

    @Test
    func `behind when nothing used late in period`() {
        // Given: 90% time elapsed, 0% used
        let pace = UsagePace.from(percentUsed: 0, percentTimeElapsed: 90)
        #expect(pace == .behind)
    }

    // MARK: - Display Properties

    @Test
    func `display names are correct`() {
        #expect(UsagePace.onPace.displayName == "On track")
        #expect(UsagePace.ahead.displayName == "Running hot")
        #expect(UsagePace.behind.displayName == "Room to spare")
        #expect(UsagePace.unknown.displayName == "Unknown")
    }

    @Test
    func `symbol names are valid SF Symbols`() {
        #expect(UsagePace.onPace.symbolName == "equal.circle.fill")
        #expect(UsagePace.ahead.symbolName == "hare.fill")
        #expect(UsagePace.behind.symbolName == "tortoise.fill")
        #expect(UsagePace.unknown.symbolName == "questionmark.circle.fill")
    }

    // MARK: - UsageQuota Pace Integration

    @Test
    func `quota percentTimeElapsed is nil without resetsAt`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.percentTimeElapsed == nil)
    }

    @Test
    func `quota percentTimeElapsed calculates correctly for session halfway through`() {
        // Session = 5 hours. If resets in 2.5 hours, we're 50% through.
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 2.5 hours from now
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51) // ~50%, allow for test execution time
    }

    @Test
    func `quota percentTimeElapsed is clamped to 0 when just reset`() {
        // Reset time is the full duration away (just started)
        let resetsAt = Date().addingTimeInterval(5 * 3600) // 5 hours from now (full session)
        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed >= 0 && elapsed < 1) // ~0%
    }

    @Test
    func `quota percentTimeElapsed is clamped to 100 when past reset time`() {
        // Reset time is in the past (timeUntilReset will be 0)
        let resetsAt = Date().addingTimeInterval(-60) // 1 minute ago
        let quota = UsageQuota(
            percentRemaining: 0,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        #expect(quota.percentTimeElapsed == 100)
    }

    @Test
    func `quota pacePercent is nil without resetsAt`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.pacePercent == nil)
    }

    @Test
    func `quota pacePercent is positive when ahead`() {
        // 50% used, ~25% time elapsed → pacePercent ≈ +25
        let resetsAt = Date().addingTimeInterval(3.75 * 3600) // 75% remaining of 5h session
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let pace = quota.pacePercent!
        #expect(pace > 20 && pace < 30) // ~25%, allow for test execution time
    }

    @Test
    func `quota pacePercent is negative when behind`() {
        // 25% used, ~50% time elapsed → pacePercent ≈ -25
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 50% remaining of 5h session
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let pace = quota.pacePercent!
        #expect(pace < -20 && pace > -30) // ~-25%
    }

    @Test
    func `quota pace is unknown without resetsAt`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.pace == .unknown)
    }

    @Test
    func `quota pace is ahead when consuming fast`() {
        // 70% used, ~25% time elapsed
        let resetsAt = Date().addingTimeInterval(3.75 * 3600)
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.pace == .ahead)
    }

    @Test
    func `quota pace is behind when consuming slow`() {
        // 10% used, ~75% time elapsed
        let resetsAt = Date().addingTimeInterval(1.25 * 3600)
        let quota = UsageQuota(
            percentRemaining: 90,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.pace == .behind)
    }

    // MARK: - Display Percent in Pace Mode

    @Test
    func `displayPercent in pace mode returns percentRemaining`() {
        let resetsAt = Date().addingTimeInterval(3.75 * 3600)
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        #expect(quota.displayPercent(mode: .pace) == 30)
    }

    @Test
    func `displayPercent in pace mode returns percentRemaining when no resetsAt`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.displayPercent(mode: .pace) == 50)
    }

    @Test
    func `displayProgressPercent in pace mode returns percentRemaining`() {
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.displayProgressPercent(mode: .pace) == 30)
    }

    // MARK: - Weekly Quota Pace

    @Test
    func `weekly quota percentTimeElapsed calculates correctly`() {
        // Weekly = 7 days. If resets in 3.5 days, we're 50% through.
        let resetsAt = Date().addingTimeInterval(3.5 * 24 * 3600)
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    // MARK: - Pace Insight

    @Test
    func `paceInsight returns nil without resetsAt`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.paceInsight == nil)
    }

    @Test
    func `paceInsight returns below expected when behind`() {
        // 10% used, ~75% time elapsed → behind, pacePercent ≈ -65
        let resetsAt = Date().addingTimeInterval(1.25 * 3600)
        let quota = UsageQuota(
            percentRemaining: 90,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        let insight = quota.paceInsight!
        #expect(insight.hasSuffix("below expected usage"))
    }

    @Test
    func `paceInsight returns above expected when ahead`() {
        // 70% used, ~25% time elapsed → ahead, pacePercent ≈ +45
        let resetsAt = Date().addingTimeInterval(3.75 * 3600)
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        let insight = quota.paceInsight!
        #expect(insight.hasSuffix("above expected usage"))
    }

    @Test
    func `paceInsight returns right on track when on pace`() {
        // 50% used, ~50% time elapsed → on pace
        let resetsAt = Date().addingTimeInterval(2.5 * 3600)
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.paceInsight == "Right on track")
    }
}
