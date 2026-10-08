import Testing
import Foundation
@testable import Quotas

@Suite
struct CostUsageTests {

    // MARK: - Initialization

    @Test
    func `should keep the cost, API and wall time, and lines added and removed`() {
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

    @Test
    func `should count a cost as API cost unless told otherwise`() {
        let cost = CostUsage(
            totalCost: 1,
            apiDuration: 0,
            providerId: "claude"
        )

        #expect(cost.kind == .apiCost)
    }

    @Test
    func `should count a cost as extra usage when told so`() {
        let cost = CostUsage(
            totalCost: 1,
            apiDuration: 0,
            providerId: "claude",
            kind: .extraUsage
        )

        #expect(cost.kind == .extraUsage)
    }

    // MARK: - Formatting

    @Test
    func `should print a cost in US dollars with two decimals`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "0.55")!,
            apiDuration: 0,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCost == "$0.55")
    }

    @Test
    func `should print a cost over a thousand dollars in US dollars`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "1234.56")!,
            apiDuration: 0,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCost == "$1,234.56")
    }


    @Test(arguments: ["0.5", "1234.567"])
    func `should print a part of the cost the same way as the whole cost`(amount: String) {
        let value = Decimal(string: amount)!
        let whole = CostUsage(totalCost: value, apiDuration: 0, providerId: "claude")
        #expect(CostLine(label: "opus", amount: value).formattedAmount == whole.formattedCost)
    }

    @Test
    func `should print API time of over an hour as hours, minutes and seconds`() {
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
    func `should print API time under an hour as minutes and seconds`() {
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
    func `should print API time under a minute as seconds`() {
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
    func `should print code changes as lines added and removed`() {
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
    func `should show what is left of the budget`() {
        let cost = CostUsage(
            totalCost: 5,
            budget: 20,
            apiDuration: 0,
            providerId: "claude"
        )

        #expect(cost.budgetRemaining == 15)
    }

    @Test
    func `should show nothing left of the budget when it is overspent`() {
        let cost = CostUsage(
            totalCost: 25,
            budget: 20,
            apiDuration: 0,
            providerId: "claude"
        )

        #expect(cost.budgetRemaining == 0)
    }

    @Test
    func `should show no budget left when there is no budget`() {
        let cost = CostUsage(
            totalCost: 5,
            apiDuration: 0,
            providerId: "claude"
        )

        #expect(cost.budgetRemaining == nil)
    }

    @Test
    func `should be within budget at half the budget`() {
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
    func `should be approaching the limit at 85 percent of the budget`() {
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
    func `should be over budget past the budget`() {
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
    func `should show half the budget used`() {
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
    func `should show no budget used when the budget is zero`() {
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
    func `should treat two costs with the same amount and time as the same, and different amounts as different`() {
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
    func `should be within budget at half the budget`() {
        // When
        let status = BudgetStatus.from(cost: 5, budget: 10)

        // Then
        #expect(status == .withinBudget)
    }

    @Test
    func `should be approaching the limit at 80 percent of the budget`() {
        // When
        let status = BudgetStatus.from(cost: 8, budget: 10)

        // Then
        #expect(status == .approachingLimit)
    }

    @Test
    func `should be over budget at exactly the budget`() {
        // When
        let status = BudgetStatus.from(cost: 10, budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `should be over budget past the budget`() {
        // When
        let status = BudgetStatus.from(cost: 15, budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `should be within budget when the budget is zero`() {
        // When
        let status = BudgetStatus.from(cost: 5, budget: 0)

        // Then
        #expect(status == .withinBudget)
    }

    // MARK: - Display Properties

    @Test
    func `should badge within budget ON TRACK`() {
        #expect(BudgetStatus.withinBudget.badgeText == "ON TRACK")
    }

    @Test
    func `should badge approaching the limit NEAR LIMIT`() {
        #expect(BudgetStatus.approachingLimit.badgeText == "NEAR LIMIT")
    }

    @Test
    func `should badge over budget OVER BUDGET`() {
        #expect(BudgetStatus.overBudget.badgeText == "OVER BUDGET")
    }

    @Test
    func `should not need attention within budget`() {
        #expect(BudgetStatus.withinBudget.needsAttention == false)
    }

    @Test
    func `should need attention approaching the limit`() {
        #expect(BudgetStatus.approachingLimit.needsAttention == true)
    }

    @Test
    func `should need attention over budget`() {
        #expect(BudgetStatus.overBudget.needsAttention == true)
    }

    // MARK: - Comparable

    @Test
    func `should rank over budget above approaching the limit above within budget`() {
        #expect(BudgetStatus.withinBudget < BudgetStatus.approachingLimit)
        #expect(BudgetStatus.approachingLimit < BudgetStatus.overBudget)
    }

    @Test
    func `should take over budget as the worst of several`() {
        let statuses: [BudgetStatus] = [.withinBudget, .approachingLimit, .overBudget]
        #expect(statuses.max() == .overBudget)
    }
}
