import Testing
import Foundation
@testable import Domain

@Suite
struct UsageQuotaTests {

    // MARK: - Creating Quotas

    @Test
    func `should hold its percent left, kind and provider, with no dollar amounts unless given`() {
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
    func `should keep the time it resets`() {
        // Given
        let resetDate = Date().addingTimeInterval(3600)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate,
            windowDuration: QuotaType.weekly.conventionalWindow.seconds
        )

        // Then — to the microsecond: the SDK's clock is Unix seconds, and moving a Date
        // between Apple's epoch and 1970 can shift its last bit.
        #expect(abs(quota.resetsAt!.timeIntervalSince(resetDate)) < 0.000_001)
    }

    @Test
    func `should print Resets in 2d 5h 30m when the reset is over a day away`() {
        // Given - 2 days, 5 hours, 30 minutes from now (+ 30s buffer to avoid rounding down)
        let resetDate = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30.0 * 60 + 30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate,
            windowDuration: QuotaType.weekly.conventionalWindow.seconds
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets in 2d 5h 30m")
    }

    @Test
    func `should print only hours and minutes when the reset is under a day away`() {
        // Given - 3 hours, 15 minutes from now (+ 30s buffer to avoid rounding down)
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 15.0 * 60 + 30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate,
            windowDuration: QuotaType.weekly.conventionalWindow.seconds
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets in 3h 15m")
    }

    @Test
    func `should print Resets soon when the reset is under a minute away`() {
        // Given - 30 seconds from now
        let resetDate = Date().addingTimeInterval(30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate,
            windowDuration: QuotaType.weekly.conventionalWindow.seconds
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets soon")
    }

    @Test
    func `should print no reset countdown when the quota has no reset time`() {
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
    func `should show 2d on the pill when the reset is over two days away`() {
        let resetDate = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate, windowDuration: QuotaType.weekly.conventionalWindow.seconds)
        #expect(quota.compactResetTime == "2d")
    }

    @Test
    func `should show 3:58 on the pill when the reset is under a day away`() {
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 58.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate, windowDuration: QuotaType.weekly.conventionalWindow.seconds)
        #expect(quota.compactResetTime == "3:58")
    }

    @Test
    func `should pad the minutes to two digits on the pill`() {
        let resetDate = Date().addingTimeInterval(5.0 * 3600 + 5.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate, windowDuration: QuotaType.weekly.conventionalWindow.seconds)
        #expect(quota.compactResetTime == "5:05")
    }

    @Test
    func `should show 3:00 on the pill when the reset is a whole number of hours away`() {
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate, windowDuration: QuotaType.weekly.conventionalWindow.seconds)
        #expect(quota.compactResetTime == "3:00")
    }

    @Test
    func `should show 45m on the pill when the reset is under an hour away`() {
        let resetDate = Date().addingTimeInterval(45.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate, windowDuration: QuotaType.weekly.conventionalWindow.seconds)
        #expect(quota.compactResetTime == "45m")
    }

    @Test
    func `should show soon on the pill when the reset is under a minute away`() {
        let resetDate = Date().addingTimeInterval(30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate, windowDuration: QuotaType.weekly.conventionalWindow.seconds)
        #expect(quota.compactResetTime == "soon")
    }

    @Test
    func `should show no reset time on the pill when the quota has no reset time`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
        #expect(quota.compactResetTime == nil)
    }

    // MARK: - Quota Types

    @Test
    func `should name the session quota Session and expect it to last 5 hours`() {
        // Given
        let quotaType = QuotaType.session

        // When & Then
        #expect(quotaType.displayName == "Session")
        #expect(quotaType.conventionalWindow == .hours(5))
    }

    @Test
    func `should name the weekly quota Weekly and expect it to last 7 days`() {
        // Given
        let quotaType = QuotaType.weekly

        // When & Then
        #expect(quotaType.displayName == "Weekly")
        #expect(quotaType.conventionalWindow == .days(7))
    }

    @Test
    func `should show a model's quota under the capitalized model name`() {
        // Given
        let quotaType = QuotaType.modelSpecific("opus")

        // When & Then
        #expect(quotaType.displayName == "Opus")
        #expect(quotaType.modelName == "opus")
    }

    // MARK: - Status Thresholds

    @Test
    func `should be healthy when more than 50 percent is left`() {
        // Given
        let quota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .healthy)
    }

    @Test
    func `should warn when between 20 and 50 percent is left`() {
        // Given
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .warning)
    }

    @Test
    func `should be critical when under 20 percent is left`() {
        // Given
        let quota = UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .critical)
    }

    @Test
    func `should be depleted when nothing is left`() {
        // Given
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .depleted)
        #expect(quota.isDepleted == true)
    }

    // MARK: - Comparing Quotas

    @Test
    func `should rank a quota with more left above one with less left`() {
        // Given
        let highQuota = UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")
        let lowQuota = UsageQuota(percentRemaining: 20, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(highQuota > lowQuota)
        #expect(lowQuota < highQuota)
    }

    @Test
    func `should treat two quotas with the same percent left as equal`() {
        // Given
        let quota1 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        let quota2 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota1 == quota2)
    }

    // MARK: - Display Percent (Remaining vs Used)

    @Test
    func `should show the percent left when the person picks remaining`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .remaining) == 75)
    }

    @Test
    func `should show the percent used when the person picks used`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .used) == 25)
    }

    @Test
    func `should show 100 percent used when nothing is left`() {
        // Given
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .used) == 100)
    }

    @Test
    func `should show 0 percent used when the quota is untouched`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .used) == 0)
    }

    @Test
    func `should show over 100 percent used when the quota is overspent`() {
        // Given - negative percentRemaining means over-quota
        let quota = UsageQuota(percentRemaining: -10, quotaType: .session, providerId: "claude")

        // When & Then - used should be 110 (over 100%)
        #expect(quota.displayPercent(mode: .used) == 110)
    }

    @Test
    func `should fill the bar with the percent left when the person picks remaining`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then - bar shares the headline number's scale
        #expect(quota.displayProgressPercent(mode: .remaining) == 75)
    }

    @Test
    func `should fill the bar with the percent used when the person picks used`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayProgressPercent(mode: .used) == 25)
    }

    // MARK: - Display Percent (Pace Mode)

    @Test
    func `should show the percent left when the person picks pace`() {
        // Given - pace mode shows familiar remaining number
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.displayPercent(mode: .pace) == 75)
    }

    @Test
    func `should fill the bar with the percent left when the person picks pace`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then - pace mode shows the remaining number, so the bar matches it
        #expect(quota.displayProgressPercent(mode: .pace) == 75)
    }

    @Test
    func `should fill the bar to the same number the card prints in every mode (#268)`() {
        // Given - regression for #268: an 87% Remaining card drew a 13% bar
        let quota = UsageQuota(percentRemaining: 87, quotaType: .session, providerId: "claude")

        // When & Then - the bar and the headline number never disagree
        for mode in UsageDisplayMode.allCases {
            #expect(quota.displayProgressPercent(mode: mode) == quota.displayPercent(mode: mode))
        }
    }

    @Test
    func `should place the pace tick on the bar's own scale in every mode`() {
        // Session is 5h. 1.25h remaining -> 75% elapsed -> tick at 25 remaining, 75 used.
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .session,
            providerId: "claude",
            resetsAt: Date().addingTimeInterval(1.25 * 3600),
            windowDuration: QuotaType.session.conventionalWindow.seconds
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
    func `should count in dollars when the provider gives a dollar balance`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: 50)

        // When & Then
        #expect(quota.isDollarBased == true)
    }

    @Test
    func `should not count in dollars when the provider gives no dollar balance`() {
        // Given
        let quota = UsageQuota(percentRemaining: 87.95, quotaType: .modelSpecific("Amp Free"), providerId: "ampcode")

        // When & Then
        #expect(quota.isDollarBased == false)
    }

    @Test
    func `should print a whole-dollar balance with two decimals`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: 50)

        // When & Then
        #expect(quota.formattedDollarRemaining == "$50.00")
    }

    @Test
    func `should print an empty balance as $0.00`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: 0)

        // When & Then
        #expect(quota.formattedDollarRemaining == "$0.00")
    }

    @Test
    func `should print a balance with cents exactly`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "ampcode", dollarRemaining: Decimal(string: "17.59"))

        // When & Then
        #expect(quota.formattedDollarRemaining == "$17.59")
    }

    @Test
    func `should print no balance when the quota is not counted in dollars`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.formattedDollarRemaining == nil)
    }

    @Test
    func `should print the balance in yuan when the provider counts in CNY`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: Decimal(110), currency: "CNY")

        // When & Then
        #expect(quota.formattedDollarRemaining == "¥110.00")
    }

    @Test
    func `should print the balance in dollars when the provider names USD or no currency`() {
        // Given
        let nilCurrency = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: Decimal(40))
        let usdCurrency = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Balance"), providerId: "deepseek", dollarRemaining: Decimal(40), currency: "USD")

        // When & Then
        #expect(nilCurrency.formattedDollarRemaining == "$40.00")
        #expect(usdCurrency.formattedDollarRemaining == "$40.00")
    }

    @Test
    func `should show the symbol for USD, CNY and EUR and the code itself for any other currency`() {
        // When & Then
        #expect(UsageQuota.currencySymbol(for: "USD") == "$")
        #expect(UsageQuota.currencySymbol(for: "CNY") == "¥")
        #expect(UsageQuota.currencySymbol(for: "cny") == "¥") // case-insensitive
        #expect(UsageQuota.currencySymbol(for: "EUR") == "€")
        #expect(UsageQuota.currencySymbol(for: "XYZ") == "XYZ ")
    }

    @Test
    func `should keep the dollars spent and the spending cap, with no balance left`() {
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
    func `should print no spend as $0.00 against a $500 cap`() {
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
    func `should know no burn rate when the quota has no reset time`() {
        let quota = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        #expect(quota.burnRate == nil)
    }

    @Test
    func `should show a burn rate near 2.8 when 70 percent is used a quarter into the window`() {
        // 70% used, ~25% time elapsed → burn rate ≈ 2.8
        let resetsAt = Date().addingTimeInterval(3.75 * 3600) // 75% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        let rate = quota.burnRate!
        #expect(rate > 2.5 && rate < 3.1) // ~2.8, allow for test execution time
    }

    @Test
    func `should show a burn rate below 1 when usage trails the time gone`() {
        // 25% used, ~50% time elapsed → burn rate ≈ 0.5
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 50% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        let rate = quota.burnRate!
        #expect(rate > 0.4 && rate < 0.6) // ~0.5
    }

    // MARK: - Pace-Aware Status

    @Test
    func `should be healthy under pace-aware when 43 percent is left late in the window`() {
        // 57% used, ~85% elapsed → burn rate ~0.67 → healthy
        let resetsAt = Date().addingTimeInterval(0.75 * 3600) // 15% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: QuotaType.session.conventionalWindow.seconds
        )
        #expect(quota.paceAwareStatus(burnRateThreshold: 1.5) == .healthy)
    }

    @Test
    func `should fall back to absolute thresholds under pace-aware when the quota has no reset time`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")
        // No reset time → falls back to absolute: 35% remaining → warning
        #expect(quota.paceAwareStatus(burnRateThreshold: 1.5) == .warning)
    }

    // MARK: - Window Duration Override

    @Test
    func `should count time gone against the window the provider reports, not the 7-day default`() {
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
    func `should count half a 7-day window gone when a time-limit quota resets in three and a half days`() {
        let resetsAt = Date().addingTimeInterval(3.5 * 24 * 3600) // half of the default 7d left
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Anything"),
            providerId: "omp",
            resetsAt: resetsAt,
            windowDuration: QuotaType.timeLimit("Anything").conventionalWindow.seconds
        )
        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    @Test
    func `should explain the pace tick as the expected percent left and say usage is below expected in remaining mode`() {
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
    func `should explain the pace tick as the expected percent used in used mode`() {
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
    func `should give the pace tick no explanation when the quota has no reset time`() {
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .timeLimit("MCP"),
            providerId: "zai"
        )
        #expect(quota.paceTickHelp(mode: .remaining) == nil)
    }

    // MARK: - Shared Reset Description

    @Test
    func `should print one reset countdown when every quota resets at the same time`() {
        let resetsAt = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30.0 * 60 + 30)
        let quotas = [
            UsageQuota(percentRemaining: 0, quotaType: .weekly, providerId: "claude", resetsAt: resetsAt, windowDuration: QuotaType.weekly.conventionalWindow.seconds),
            UsageQuota(percentRemaining: 13, quotaType: .timeLimit("Build"), providerId: "claude", resetsAt: resetsAt, windowDuration: QuotaType.timeLimit("Build").conventionalWindow.seconds),
            UsageQuota(percentRemaining: 93, quotaType: .timeLimit("Chat"), providerId: "claude", resetsAt: resetsAt, windowDuration: QuotaType.timeLimit("Chat").conventionalWindow.seconds)
        ]

        #expect(quotas.sharedResetDescription() == "Resets in 2d 5h 30m")
    }

    @Test
    func `should print one reset countdown when the quotas reset within a minute of each other`() {
        let base = Date().addingTimeInterval(3.0 * 3600 + 15.0 * 60 + 30)
        let quotas = [
            UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude", resetsAt: base, windowDuration: QuotaType.weekly.conventionalWindow.seconds),
            UsageQuota(percentRemaining: 20, quotaType: .timeLimit("Build"), providerId: "claude", resetsAt: base.addingTimeInterval(30), windowDuration: QuotaType.timeLimit("Build").conventionalWindow.seconds)
        ]

        #expect(quotas.sharedResetDescription() == "Resets in 3h 15m")
    }

    @Test
    func `should print no shared countdown when the quotas reset at different times`() {
        let weekly = Date().addingTimeInterval(3 * 86400)
        let session = Date().addingTimeInterval(4 * 3600)
        let quotas = [
            UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude", resetsAt: weekly, windowDuration: QuotaType.weekly.conventionalWindow.seconds),
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude", resetsAt: session, windowDuration: QuotaType.session.conventionalWindow.seconds)
        ]

        #expect(quotas.sharedResetDescription() == nil)
    }

    @Test
    func `should print no shared countdown for a single quota`() {
        let quotas = [
            UsageQuota(
                percentRemaining: 10,
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(86400),
                windowDuration: QuotaType.weekly.conventionalWindow.seconds
            )
        ]

        #expect(quotas.sharedResetDescription() == nil)
    }

    @Test
    func `should print no shared countdown when any quota has no reset time`() {
        let resetsAt = Date().addingTimeInterval(86400)
        let quotas = [
            UsageQuota(percentRemaining: 10, quotaType: .weekly, providerId: "claude", resetsAt: resetsAt, windowDuration: QuotaType.weekly.conventionalWindow.seconds),
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")
        ]

        #expect(quotas.sharedResetDescription() == nil)
    }
}
