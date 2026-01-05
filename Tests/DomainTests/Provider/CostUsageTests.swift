import Testing
import Foundation
@testable import Domain

@Suite
struct CostUsageTests {

    // MARK: - Initialization

    @Test
    func `creates cost usage with all fields`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "5.50")!,
            apiDuration: 3600,
            wallDuration: 7200,
            linesAdded: 100,
            linesRemoved: 50,
            providerId: "claude"
        )

        // Then
        #expect(cost.totalCost == Decimal(string: "5.50"))
        #expect(cost.apiDuration == 3600)
        #expect(cost.wallDuration == 7200)
        #expect(cost.linesAdded == 100)
        #expect(cost.linesRemoved == 50)
        #expect(cost.providerId == "claude")
    }

    // MARK: - Formatting

    @Test
    func `formats cost as currency`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "0.55")!,
            apiDuration: 0,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCost == Self.expectedCurrencyString(for: Decimal(string: "0.55")!))
    }

    @Test
    func `formats large cost as currency`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "1234.56")!,
            apiDuration: 0,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCost == Self.expectedCurrencyString(for: Decimal(string: "1234.56")!))
    }

    private static func expectedCurrencyString(for value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    @Test
    func `formats API duration with hours minutes seconds`() {
        // Given
        let cost = CostUsage(
            totalCost: 0,
            apiDuration: 3661.5, // 1h 1m 1.5s
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedApiDuration == "1h 1m 1.5s")
    }

    @Test
    func `formats API duration with minutes and seconds only`() {
        // Given
        let cost = CostUsage(
            totalCost: 0,
            apiDuration: 379.7, // 6m 19.7s
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedApiDuration == "6m 19.7s")
    }

    @Test
    func `formats API duration with seconds only`() {
        // Given
        let cost = CostUsage(
            totalCost: 0,
            apiDuration: 45.2,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedApiDuration == "45.2s")
    }

    @Test
    func `formats code changes`() {
        // Given
        let cost = CostUsage(
            totalCost: 0,
            apiDuration: 0,
            wallDuration: 0,
            linesAdded: 150,
            linesRemoved: 42,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCodeChanges == "+150 / -42 lines")
    }

    // MARK: - Budget Calculation

    @Test
    func `calculates budget status within budget`() {
        // Given
        let cost = CostUsage(
            totalCost: 5,
            apiDuration: 0,
            providerId: "claude"
        )

        // When
        let status = cost.budgetStatus(budget: 10)

        // Then
        #expect(status == .withinBudget)
    }

    @Test
    func `calculates budget status approaching limit`() {
        // Given
        let cost = CostUsage(
            totalCost: 8.5,
            apiDuration: 0,
            providerId: "claude"
        )

        // When
        let status = cost.budgetStatus(budget: 10)

        // Then
        #expect(status == .approachingLimit)
    }

    @Test
    func `calculates budget status over budget`() {
        // Given
        let cost = CostUsage(
            totalCost: 12,
            apiDuration: 0,
            providerId: "claude"
        )

        // When
        let status = cost.budgetStatus(budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `calculates budget percent used`() {
        // Given
        let cost = CostUsage(
            totalCost: 5,
            apiDuration: 0,
            providerId: "claude"
        )

        // When
        let percent = cost.budgetPercentUsed(budget: 10)

        // Then
        #expect(percent == 50)
    }

    @Test
    func `budget percent used handles zero budget`() {
        // Given
        let cost = CostUsage(
            totalCost: 5,
            apiDuration: 0,
            providerId: "claude"
        )

        // When
        let percent = cost.budgetPercentUsed(budget: 0)

        // Then
        #expect(percent == 0)
    }

    // MARK: - Equatable

    @Test
    func `cost usage is equatable`() {
        // Given
        let capturedAt = Date()
        let cost1 = CostUsage(totalCost: 5, apiDuration: 100, providerId: "claude", capturedAt: capturedAt)
        let cost2 = CostUsage(totalCost: 5, apiDuration: 100, providerId: "claude", capturedAt: capturedAt)
        let cost3 = CostUsage(totalCost: 10, apiDuration: 100, providerId: "claude", capturedAt: capturedAt)

        // Then
        #expect(cost1 == cost2)
        #expect(cost1 != cost3)
    }
}

@Suite
struct BudgetStatusTests {

    // MARK: - Factory Method

    @Test
    func `creates within budget status for low usage`() {
        // When
        let status = BudgetStatus.from(cost: 5, budget: 10)

        // Then
        #expect(status == .withinBudget)
    }

    @Test
    func `creates approaching limit status at 80 percent`() {
        // When
        let status = BudgetStatus.from(cost: 8, budget: 10)

        // Then
        #expect(status == .approachingLimit)
    }

    @Test
    func `creates over budget status at 100 percent`() {
        // When
        let status = BudgetStatus.from(cost: 10, budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `creates over budget status when exceeding budget`() {
        // When
        let status = BudgetStatus.from(cost: 15, budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `handles zero budget gracefully`() {
        // When
        let status = BudgetStatus.from(cost: 5, budget: 0)

        // Then
        #expect(status == .withinBudget)
    }

    // MARK: - Display Properties

    @Test
    func `badge text for within budget`() {
        #expect(BudgetStatus.withinBudget.badgeText == "ON TRACK")
    }

    @Test
    func `badge text for approaching limit`() {
        #expect(BudgetStatus.approachingLimit.badgeText == "NEAR LIMIT")
    }

    @Test
    func `badge text for over budget`() {
        #expect(BudgetStatus.overBudget.badgeText == "OVER BUDGET")
    }

    @Test
    func `needs attention for within budget is false`() {
        #expect(BudgetStatus.withinBudget.needsAttention == false)
    }

    @Test
    func `needs attention for approaching limit is true`() {
        #expect(BudgetStatus.approachingLimit.needsAttention == true)
    }

    @Test
    func `needs attention for over budget is true`() {
        #expect(BudgetStatus.overBudget.needsAttention == true)
    }

    // MARK: - Comparable

    @Test
    func `budget status is comparable by severity`() {
        #expect(BudgetStatus.withinBudget < BudgetStatus.approachingLimit)
        #expect(BudgetStatus.approachingLimit < BudgetStatus.overBudget)
    }

    @Test
    func `max of budget statuses returns worst`() {
        let statuses: [BudgetStatus] = [.withinBudget, .approachingLimit, .overBudget]
        #expect(statuses.max() == .overBudget)
    }
}
