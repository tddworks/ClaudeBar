import Testing
import Foundation
@testable import Domain

@Suite
struct UsageQuotaTests {

    // MARK: - Creating Quotas

    @Test
    func `quota can be created with percentage and type`() {
        // Given
        let percentRemaining = 65.0
        let quotaType = QuotaType.session
        let providerId = "claude"

        // When
        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: quotaType,
            providerId: providerId
        )

        // Then
        #expect(quota.percentRemaining == 65)
        #expect(quota.quotaType == QuotaType.session)
        #expect(quota.providerId == "claude")
    }

    @Test
    func `quota can include reset time`() {
        // Given
        let resetDate = Date().addingTimeInterval(3600)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetsAt == resetDate)
    }

    @Test
    func `quota reset timestamp shows days hours and minutes`() {
        // Given - 2 days, 5 hours, 30 minutes from now (+ 30s buffer to avoid rounding down)
        let resetDate = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30.0 * 60 + 30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets in 2d 5h 30m")
    }

    @Test
    func `quota reset timestamp shows only hours and minutes when less than a day`() {
        // Given - 3 hours, 15 minutes from now (+ 30s buffer to avoid rounding down)
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 15.0 * 60 + 30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets in 3h 15m")
    }

    @Test
    func `quota reset timestamp shows resets soon when under a minute`() {
        // Given - 30 seconds from now
        let resetDate = Date().addingTimeInterval(30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets soon")
    }

    @Test
    func `quota reset timestamp description is nil without reset date`() {
        // Given
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude"
        )

        // Then
        #expect(quota.resetTimestampDescription == nil)
    }

    // MARK: - Quota Types

    @Test
    func `session quota represents a 5 hour window`() {
        // Given
        let quotaType = QuotaType.session

        // When & Then
        #expect(quotaType.displayName == "Session")
        #expect(quotaType.duration == .hours(5))
    }

    @Test
    func `weekly quota represents a 7 day window`() {
        // Given
        let quotaType = QuotaType.weekly

        // When & Then
        #expect(quotaType.displayName == "Weekly")
        #expect(quotaType.duration == .days(7))
    }

    @Test
    func `model specific quota shows the model name`() {
        // Given
        let quotaType = QuotaType.modelSpecific("opus")

        // When & Then
        #expect(quotaType.displayName == "Opus")
        #expect(quotaType.modelName == "opus")
    }

    // MARK: - Status Thresholds

    @Test
    func `quota with more than 50 percent remaining is healthy`() {
        // Given
        let quota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .healthy)
    }

    @Test
    func `quota between 20 and 50 percent remaining shows warning`() {
        // Given
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .warning)
    }

    @Test
    func `quota below 20 percent remaining is critical`() {
        // Given
        let quota = UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .critical)
    }

    @Test
    func `quota at zero percent is depleted`() {
        // Given
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .depleted)
        #expect(quota.isDepleted == true)
    }

    // MARK: - Comparing Quotas

    @Test
    func `quotas can be sorted by percentage remaining`() {
        // Given
        let highQuota = UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")
        let lowQuota = UsageQuota(percentRemaining: 20, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(highQuota > lowQuota)
        #expect(lowQuota < highQuota)
    }

    @Test
    func `quotas with same percentage are equal`() {
        // Given
        let quota1 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        let quota2 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota1 == quota2)
    }

    // MARK: - Display Percent (Remaining vs Used)

    @Test
    func `displayPercent returns percentRemaining in remaining mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .remaining) == 75)
    }

    @Test
    func `displayPercent returns percentUsed in used mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .used) == 25)
    }

    @Test
    func `displayPercent handles zero remaining in used mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .used) == 100)
    }

    @Test
    func `displayPercent handles full quota in used mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .used) == 0)
    }

    @Test
    func `displayPercent handles negative remaining in used mode`() {
        // Given - negative percentRemaining means over-quota
        let quota = UsageQuota(percentRemaining: -10, quotaType: .session, providerId: "claude")

        // When & Then - used should be 110 (over 100%)
        #expect(quota.displayPercent(mode: .used) == 110)
    }

    @Test
    func `displayProgressPercent returns percentRemaining in remaining mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayProgressPercent(mode: .remaining) == 75)
    }

    @Test
    func `displayProgressPercent returns percentUsed in used mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayProgressPercent(mode: .used) == 25)
    }

    // MARK: - Display Percent (Pace Mode)

    @Test
    func `displayPercent returns percentRemaining in pace mode`() {
        // Given - pace mode shows familiar remaining number
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .pace) == 75)
    }

    @Test
    func `displayProgressPercent returns percentRemaining in pace mode`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then - pace mode progress bar shows remaining (same as remaining mode)
        #expect(quota.displayProgressPercent(mode: .pace) == 75)
    }

    // MARK: - Dollar-Based Quotas

    @Test
    func `isDollarBased returns true when dollarRemaining is set`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: 50)

        // When & Then
        #expect(quota.isDollarBased == true)
    }

    @Test
    func `isDollarBased returns false when dollarRemaining is nil`() {
        // Given
        let quota = UsageQuota(percentRemaining: 87.95, quotaType: .modelSpecific("Amp Free"), providerId: "ampcode")

        // When & Then
        #expect(quota.isDollarBased == false)
    }

    @Test
    func `formattedDollarRemaining formats whole dollars`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: 50)

        // When & Then
        #expect(quota.formattedDollarRemaining == "$50.00")
    }

    @Test
    func `formattedDollarRemaining formats zero`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: 0)

        // When & Then
        #expect(quota.formattedDollarRemaining == "$0.00")
    }

    @Test
    func `formattedDollarRemaining formats decimal amount`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: Decimal(string: "17.59"))

        // When & Then
        #expect(quota.formattedDollarRemaining == "$17.59")
    }

    @Test
    func `formattedDollarRemaining returns nil when not dollar based`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.formattedDollarRemaining == nil)
    }
}
