import Foundation
import QuotaKernel

extension BudgetStatus: @retroactive Comparable {
    /// The status of a cost against a budget.
    public static func from(cost: Decimal, budget: Decimal) -> BudgetStatus {
        BudgetStatus.companion.from(costNanos: cost.nanos, budgetNanos: budget.nanos)
    }

    /// Higher is worse.
    public var severity: Int { Int(ordinal) }

    public var rawValue: String {
        switch self {
        case .withinBudget: "withinBudget"
        case .approachingLimit: "approachingLimit"
        case .overBudget: "overBudget"
        }
    }

    public init?(rawValue: String) {
        guard let status = BudgetStatus.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = status
    }

    public static func < (lhs: BudgetStatus, rhs: BudgetStatus) -> Bool { lhs.ordinal < rhs.ordinal }
}

extension CostLine {
    public convenience init(label: String, amount: Decimal, detail: String? = nil) {
        self.init(label: label, amountNanos: amount.nanos, detail: detail)
    }

    public static func == (lhs: CostLine, rhs: CostLine) -> Bool { lhs.isEqual(rhs) }

    public var amount: Decimal { Decimal(nanos: amountNanos) }
    /// "$0.55"
    public var formattedAmount: String { formattedUSD(amount) }
}

extension CostUsage {
    public convenience init(
        totalCost: Decimal,
        budget: Decimal? = nil,
        apiDuration: TimeInterval,
        wallDuration: TimeInterval = 0,
        linesAdded: Int = 0,
        linesRemoved: Int = 0,
        providerId: String,
        kind: Kind = .apiCost,
        capturedAt: Date = Date(),
        resetsAt: Date? = nil,
        resetText: String? = nil,
        lines: [CostLine] = []
    ) {
        self.init(
            totalCostNanos: totalCost.nanos,
            budgetNanos: budget.map(\.nanos).kotlin,
            apiDuration: apiDuration,
            wallDuration: wallDuration,
            linesAdded64: Int64(linesAdded),
            linesRemoved64: Int64(linesRemoved),
            providerId: providerId,
            kind: kind,
            capturedAtSeconds: capturedAt.kernelSeconds,
            resetsAtSeconds: resetsAt.map(\.kernelSeconds).kotlin,
            resetText: resetText,
            lines: lines
        )
    }

    public static func == (lhs: CostUsage, rhs: CostUsage) -> Bool { lhs.isEqual(rhs) }

    /// The total spent.
    public var totalCost: Decimal { Decimal(nanos: totalCostNanos) }
    /// The built-in budget (Pro extra usage); nil for API accounts.
    public var budget: Decimal? { budgetNanos.swift.map(Decimal.init(nanos:)) }
    public var linesAdded: Int { Int(linesAdded64) }
    public var linesRemoved: Int { Int(linesRemoved64) }
    public var capturedAt: Date { Date(kernelSeconds: capturedAtSeconds) }
    public var resetsAt: Date? { resetsAtSeconds.swift.map(Date.init(kernelSeconds:)) }

    public func budgetStatus(budget: Decimal) -> BudgetStatus { budgetStatus(budgetNanos: budget.nanos) }
    public func budgetPercentUsed(budget: Decimal) -> Double { budgetPercentUsed(budgetNanos: budget.nanos) }
    /// The unspent built-in budget, never below zero.
    public var budgetRemaining: Decimal? { budgetRemainingNanos.swift.map(Decimal.init(nanos:)) }

    /// "$0.55"
    public var formattedCost: String { formattedUSD(totalCost) }
    /// "6m 19.7s"
    public var formattedApiDuration: String {
        let hours = Int(apiDuration) / 3600
        let minutes = Int(apiDuration) / 60 % 60
        let seconds = apiDuration.truncatingRemainder(dividingBy: 60)
        if hours > 0 { return String(format: "%dh %dm %.1fs", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %.1fs", minutes, seconds) }
        return String(format: "%.1fs", seconds)
    }
    /// "+10 / -5 lines"
    public var formattedCodeChanges: String { "+\(linesAdded) / -\(linesRemoved) lines" }
}
