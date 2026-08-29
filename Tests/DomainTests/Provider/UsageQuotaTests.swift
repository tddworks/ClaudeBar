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
        #expect(quota.dollarUsed == nil)
        #expect(quota.dollarCap == nil)
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

    // MARK: - Compact Reset Time

    @Test
    func `compactResetTime shows days when over a day remains`() {
        let resetDate = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "2d")
    }

    @Test
    func `compactResetTime shows hours and minutes when under a day`() {
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "3:58")
    }

    @Test
    func `compactResetTime pads minutes to two digits`() {
        let resetDate = Date().addingTimeInterval(5.0 * 3600 + 5.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "5:05")
    }

    @Test
    func `compactResetTime shows whole hours with zero minutes`() {
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "3:00")
    }

    @Test
    func `compactResetTime shows minutes when under an hour`() {
        let resetDate = Date().addingTimeInterval(45.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "45m")
    }

    @Test
    func `compactResetTime shows soon when under a minute`() {
        let resetDate = Date().addingTimeInterval(30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "soon")
    }

    @Test
    func `compactResetTime is nil without reset date`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
        #expect(quota.compactResetTime == nil)
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

        // When & Then - bar shares the headline number's scale
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

        // When & Then - pace mode shows the remaining number, so the bar matches it
        #expect(quota.displayProgressPercent(mode: .pace) == 75)
    }

    @Test
    func `displayProgressPercent matches displayPercent in every mode`() {
        // Given - regression for #268: an 87% Remaining card drew a 13% bar
        let quota = UsageQuota(percentRemaining: 87, quotaType: .session, providerId: "claude")

        // When & Then - the bar and the headline number never disagree
        for mode in UsageDisplayMode.allCases {
            #expect(quota.displayProgressPercent(mode: mode) == quota.displayPercent(mode: mode))
        }
    }

    @Test
    func `expectedProgressPercent puts the tick on the bar's own scale`() {
        // Session is 5h. 1.25h remaining -> 75% elapsed -> tick at 25 remaining, 75 used.
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .session,
            providerId: "claude",
            resetsAt: Date().addingTimeInterval(1.25 * 3600)
        )
        let expectedRemaining = quota.expectedProgressPercent(mode: .remaining)!
        let expectedUsed = quota.expectedProgressPercent(mode: .used)!
        let expectedPace = quota.expectedProgressPercent(mode: .pace)!
        #expect(expectedRemaining > 24 && expectedRemaining < 26)
        #expect(expectedUsed > 74 && expectedUsed < 76)
        #expect(expectedPace > 24 && expectedPace < 26)
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

    @Test
    func `formattedDollarRemaining uses CNY symbol when currency is CNY`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: Decimal(110), currency: "CNY")

        // When & Then
        #expect(quota.formattedDollarRemaining == "¥110.00")
    }

    @Test
    func `formattedDollarRemaining defaults to dollar symbol when currency is nil or USD`() {
        // Given
        let nilCurrency = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: Decimal(40))
        let usdCurrency = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: Decimal(40), currency: "USD")

        // When & Then
        #expect(nilCurrency.formattedDollarRemaining == "$40.00")
        #expect(usdCurrency.formattedDollarRemaining == "$40.00")
    }

    @Test
    func `currencySymbol maps common codes and falls back to code`() {
        // When & Then
        #expect(UsageQuota.currencySymbol(for: "USD") == "$")
        #expect(UsageQuota.currencySymbol(for: "CNY") == "¥")
        #expect(UsageQuota.currencySymbol(for: "cny") == "¥") // case-insensitive
        #expect(UsageQuota.currencySymbol(for: "EUR") == "€")
        #expect(UsageQuota.currencySymbol(for: "XYZ") == "XYZ ")
    }

    @Test
    func `quota stores capped dollar spend amounts`() {
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .timeLimit("Claude Extra"),
            providerId: "omp",
            dollarUsed: Decimal(string: "123.45"),
            dollarCap: 500
        )

        #expect(quota.dollarUsed == Decimal(string: "123.45"))
        #expect(quota.dollarCap == 500)
        #expect(quota.dollarRemaining == nil)
    }

    @Test
    func `formats capped zero spend at a glance`() {
        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Claude Extra"),
            providerId: "omp",
            dollarUsed: 0,
            dollarCap: 500
        )

        #expect(quota.formattedDollarUsed == "$0.00")
        #expect(quota.formattedDollarCap == "$500")
    }

    // MARK: - Burn Rate

    @Test
    func `burnRate is nil without resetsAt`() {
        let quota = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        #expect(quota.burnRate == nil)
    }

    @Test
    func `burnRate is calculated correctly when consuming faster than time`() {
        // 70% used, ~25% time elapsed → burn rate ≈ 2.8
        let resetsAt = Date().addingTimeInterval(3.75 * 3600) // 75% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        let rate = quota.burnRate!
        #expect(rate > 2.5 && rate < 3.1) // ~2.8, allow for test execution time
    }

    @Test
    func `burnRate is below 1 when consuming slower than time`() {
        // 25% used, ~50% time elapsed → burn rate ≈ 0.5
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 50% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        let rate = quota.burnRate!
        #expect(rate > 0.4 && rate < 0.6) // ~0.5
    }

    // MARK: - Pace-Aware Status

    @Test
    func `paceAwareStatus returns healthy when burn rate is low`() {
        // 57% used, ~85% elapsed → burn rate ~0.67 → healthy
        let resetsAt = Date().addingTimeInterval(0.75 * 3600) // 15% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.paceAwareStatus(burnRateThreshold: 1.5) == .healthy)
    }

    @Test
    func `paceAwareStatus falls back to absolute thresholds without resetsAt`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")
        // No reset time → falls back to absolute: 35% remaining → warning
        #expect(quota.paceAwareStatus(burnRateThreshold: 1.5) == .warning)
    }

    // MARK: - Window Duration Override

    @Test
    func `percentTimeElapsed uses explicit windowDuration over quota type duration`() {
        // A .timeLimit quota defaults to a 7-day window; an explicit 5h
        // window (as reported by aggregating probes like Oh My Pi) must win.
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // half of a 5h window left
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Claude 5h"),
            providerId: "omp",
            resetsAt: resetsAt,
            windowDuration: 5 * 3600
        )
        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    @Test
    func `percentTimeElapsed falls back to quota type duration without windowDuration`() {
        let resetsAt = Date().addingTimeInterval(3.5 * 24 * 3600) // half of the default 7d left
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Anything"),
            providerId: "omp",
            resetsAt: resetsAt
        )
        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    @Test
    func `paceTickHelp explains expected remaining in remaining mode`() {
        // 75% of a 5h window elapsed -> steady usage would leave ~25% remaining.
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .timeLimit("Z.ai 5h"),
            providerId: "zai",
            resetsAt: Date().addingTimeInterval(1.25 * 3600),
            windowDuration: 5 * 3600
        )
        let help = quota.paceTickHelp(mode: .remaining)!
        #expect(help.contains("~25%"))
        #expect(help.contains("remaining"))
        // 57 used vs 75 elapsed -> below expected usage, surfaced inline.
        #expect(help.contains("below expected usage"))
    }

    @Test
    func `paceTickHelp uses consumed wording in used mode`() {
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .timeLimit("Z.ai 5h"),
            providerId: "zai",
            resetsAt: Date().addingTimeInterval(1.25 * 3600),
            windowDuration: 5 * 3600
        )
        let help = quota.paceTickHelp(mode: .used)!
        #expect(help.contains("~75%"))
        #expect(help.contains("used"))
    }

    @Test
    func `paceTickHelp is nil without reset time`() {
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .timeLimit("MCP"),
            providerId: "zai"
        )
        #expect(quota.paceTickHelp(mode: .remaining) == nil)
    }

    // MARK: - Shared Reset Description

    @Test
    func `sharedResetDescription returns countdown when all quotas share a reset`() {
        let resetsAt = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30.0 * 60 + 30)
        let quotas = [
            UsageQuota(percentRemaining: 0, quotaType: .weekly, providerId: "claude", resetsAt: resetsAt),
            UsageQuota(percentRemaining: 13, quotaType: .timeLimit("Build"), providerId: "claude", resetsAt: resetsAt),
            UsageQuota(percentRemaining: 93, quotaType: .timeLimit("Chat"), providerId: "claude", resetsAt: resetsAt)
        ]

        #expect(quotas.sharedResetDescription() == "Resets in 2d 5h 30m")
    }

    @Test
    func `sharedResetDescription returns countdown when resets are within 60 seconds`() {
        let base = Date().addingTimeInterval(3.0 * 3600 + 15.0 * 60 + 30)
        let quotas = [
            UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude", resetsAt: base),
            UsageQuota(percentRemaining: 20, quotaType: .timeLimit("Build"), providerId: "claude", resetsAt: base.addingTimeInterval(30))
        ]

        #expect(quotas.sharedResetDescription() == "Resets in 3h 15m")
    }

    @Test
    func `sharedResetDescription is nil when reset windows differ`() {
        let weekly = Date().addingTimeInterval(3 * 86400)
        let session = Date().addingTimeInterval(4 * 3600)
        let quotas = [
            UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude", resetsAt: weekly),
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude", resetsAt: session)
        ]

        #expect(quotas.sharedResetDescription() == nil)
    }

    @Test
    func `sharedResetDescription is nil for a single quota`() {
        let quotas = [
            UsageQuota(
                percentRemaining: 10,
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(86400)
            )
        ]

        #expect(quotas.sharedResetDescription() == nil)
    }

    @Test
    func `sharedResetDescription is nil when any quota lacks resetsAt`() {
        let resetsAt = Date().addingTimeInterval(86400)
        let quotas = [
            UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude", resetsAt: resetsAt),
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")
        ]

        #expect(quotas.sharedResetDescription() == nil)
    }
}
