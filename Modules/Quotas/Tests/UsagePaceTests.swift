import Testing
import Foundation
@testable import Quotas

@Suite
struct UsagePaceTests {

    // MARK: - Factory Method

    @Test
    func `should be on pace when usage is within 5 points of the time gone`() {
        // 52% used at 50% gone: close enough to the line to last until the reset
        #expect(UsagePace.from(percentUsed: 52, percentTimeElapsed: 50) == .onPace)
        #expect(UsagePace.from(percentUsed: 46, percentTimeElapsed: 50) == .onPace)
    }

    @Test
    func `should be on pace when usage equals the time gone`() {
        let pace = UsagePace.from(percentUsed: 50, percentTimeElapsed: 50)
        #expect(pace == .onPace)
    }

    @Test
    func `should still be on pace when usage is exactly 5 points ahead of the time gone`() {
        #expect(UsagePace.from(percentUsed: 55, percentTimeElapsed: 50) == .onPace)
    }

    @Test
    func `should still be on pace when usage is exactly 5 points behind the time gone`() {
        #expect(UsagePace.from(percentUsed: 45, percentTimeElapsed: 50) == .onPace)
    }

    @Test
    func `should run hot when usage is just over 5 points ahead of the time gone`() {
        #expect(UsagePace.from(percentUsed: 55.1, percentTimeElapsed: 50) == .ahead)
        #expect(UsagePace.from(percentUsed: 56, percentTimeElapsed: 50) == .ahead)
    }

    @Test
    func `should have no pace before 3 percent of the window has gone`() {
        // A minute into a week is noise, not a pace
        #expect(UsagePace.from(percentUsed: 1, percentTimeElapsed: 0.01) == .unknown)
    }

    @Test
    func `should run ahead when usage outpaces the time gone`() {
        // Given: 30% time elapsed, 50% used
        let pace = UsagePace.from(percentUsed: 50, percentTimeElapsed: 30)

        // Then
        #expect(pace == .ahead)
    }

    @Test
    func `should run behind when usage trails the time gone`() {
        // Given: 50% time elapsed, 30% used
        let pace = UsagePace.from(percentUsed: 30, percentTimeElapsed: 50)

        // Then
        #expect(pace == .behind)
    }

    @Test
    func `should run behind when usage is just over 5 points behind the time gone`() {
        // -5.1% difference (just beyond 5% threshold)
        #expect(UsagePace.from(percentUsed: 44.9, percentTimeElapsed: 50) == .behind)
        #expect(UsagePace.from(percentUsed: 44, percentTimeElapsed: 50) == .behind)
    }

    @Test
    func `should run ahead when the quota is used up early in the window`() {
        // Given: 10% time elapsed, 100% used
        let pace = UsagePace.from(percentUsed: 100, percentTimeElapsed: 10)
        #expect(pace == .ahead)
    }

    @Test
    func `should run behind when nothing is used late in the window`() {
        // Given: 90% time elapsed, 0% used
        let pace = UsagePace.from(percentUsed: 0, percentTimeElapsed: 90)
        #expect(pace == .behind)
    }

    // MARK: - Display Properties

    @Test
    func `should print the pace as On track, Running hot, Room to spare or Unknown`() {
        #expect(UsagePace.onPace.displayName == "On track")
        #expect(UsagePace.ahead.displayName == "Running hot")
        #expect(UsagePace.behind.displayName == "Room to spare")
        #expect(UsagePace.unknown.displayName == "Unknown")
    }

    @Test
    func `should show an equals sign, a hare, a tortoise or a question mark for the pace`() {
        #expect(UsagePace.onPace.symbolName == "equal.circle.fill")
        #expect(UsagePace.ahead.symbolName == "hare.fill")
        #expect(UsagePace.behind.symbolName == "tortoise.fill")
        #expect(UsagePace.unknown.symbolName == "questionmark.circle.fill")
    }

    // MARK: - UsageQuota Pace Integration

    @Test
    func `should know no time gone when the quota has no reset time`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.percentTimeElapsed == nil)
    }

    @Test
    func `should count half the window gone when the session resets in two and a half hours`() {
        // Session = 5 hours. If resets in 2.5 hours, we're 50% through.
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 2.5 hours from now
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51) // ~50%, allow for test execution time
    }

    @Test
    func `should count no time gone when the session has just reset`() {
        // Reset time is the full duration away (just started)
        let resetsAt = Date().addingTimeInterval(5 * 3600) // 5 hours from now (full session)
        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed >= 0 && elapsed < 1) // ~0%
    }

    @Test
    func `should count the whole window gone when the reset time has passed`() {
        // Reset time is in the past (timeUntilReset will be 0)
        let resetsAt = Date().addingTimeInterval(-60) // 1 minute ago
        let quota = UsageQuota(
            percentRemaining: 0,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )

        #expect(quota.percentTimeElapsed == 100)
    }

    @Test
    func `should know no pace gap when the quota has no reset time`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.pacePercent == nil)
    }

    @Test
    func `should show a positive pace gap when usage runs ahead of the time gone`() {
        // 50% used, ~25% time elapsed → pacePercent ≈ +25
        let resetsAt = Date().addingTimeInterval(3.75 * 3600) // 75% remaining of 5h session
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )

        let pace = quota.pacePercent!
        #expect(pace > 20 && pace < 30) // ~25%, allow for test execution time
    }

    @Test
    func `should show a negative pace gap when usage trails the time gone`() {
        // 25% used, ~50% time elapsed → pacePercent ≈ -25
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 50% remaining of 5h session
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )

        let pace = quota.pacePercent!
        #expect(pace < -20 && pace > -30) // ~-25%
    }

    @Test
    func `should show an unknown pace when the quota has no reset time`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.pace == .unknown)
    }

    @Test
    func `should show the quota running ahead when it is used fast`() {
        // 70% used, ~25% time elapsed
        let resetsAt = Date().addingTimeInterval(3.75 * 3600)
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        #expect(quota.pace == .ahead)
    }

    @Test
    func `should show the quota running behind when it is used slowly`() {
        // 10% used, ~75% time elapsed
        let resetsAt = Date().addingTimeInterval(1.25 * 3600)
        let quota = UsageQuota(
            percentRemaining: 90,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        #expect(quota.pace == .behind)
    }

    // MARK: - Display Percent in Pace Mode

    @Test
    func `should show the percent left when the person picks pace mode`() {
        let resetsAt = Date().addingTimeInterval(3.75 * 3600)
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )

        #expect(quota.displayPercent(mode: .pace) == 30)
    }

    @Test
    func `should show the percent left in pace mode when the quota has no reset time`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.displayPercent(mode: .pace) == 50)
    }

    @Test
    func `should fill the progress bar with the percent left in pace mode`() {
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.displayProgressPercent(mode: .pace) == 30)
    }

    // MARK: - Weekly Quota Pace

    @Test
    func `should count half the week gone when the weekly quota resets in three and a half days`() {
        // Weekly = 7 days. If resets in 3.5 days, we're 50% through.
        let resetsAt = Date().addingTimeInterval(3.5 * 24 * 3600)
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.weekly.conventionalWindow.seconds
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    // MARK: - Pace Insight

    @Test
    func `should give no pace insight when the quota has no reset time`() {
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude"
        )
        #expect(quota.paceInsight == nil)
    }

    @Test
    func `should say usage is below expected when it trails the time gone`() {
        // 10% used, ~75% time elapsed → behind, pacePercent ≈ -65
        let resetsAt = Date().addingTimeInterval(1.25 * 3600)
        let quota = UsageQuota(
            percentRemaining: 90,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        let insight = quota.paceInsight!
        #expect(insight.hasSuffix("below expected usage"))
    }

    @Test
    func `should say usage is above expected when it runs ahead of the time gone`() {
        // 70% used, ~25% time elapsed → ahead, pacePercent ≈ +45
        let resetsAt = Date().addingTimeInterval(3.75 * 3600)
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        let insight = quota.paceInsight!
        #expect(insight.hasSuffix("above expected usage"))
    }

    @Test
    func `should say Right on track when usage matches the time gone`() {
        // 50% used, ~50% time elapsed → on pace
        let resetsAt = Date().addingTimeInterval(2.5 * 3600)
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        #expect(quota.paceInsight == "Right on track")
    }
}
