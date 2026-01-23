import Foundation

// MARK: - Shared Formatters

/// Cached formatters for Bedrock models to avoid recreation overhead
private enum BedrockFormatters {
    /// Cached currency formatter for USD
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// Format a token count for display (e.g., "1.2M" or "500K")
    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }

    /// Format a price with currency symbol
    static func formatCurrency(_ amount: Decimal) -> String {
        currency.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}

// MARK: - BedrockModel

/// Represents an AWS Bedrock model with its pricing information.
/// Model IDs follow AWS format: provider.model-name-version
public struct BedrockModel: Sendable, Equatable, Hashable, Identifiable {
    /// The AWS model ID (e.g., "anthropic.claude-opus-4-5-20251101-v1:0")
    public let id: String

    /// Human-readable name (e.g., "Claude Opus 4.5")
    public let displayName: String

    /// Provider/vendor name (e.g., "Anthropic", "Amazon", "Meta")
    public let vendor: String

    /// Price per 1M input tokens in USD
    public let inputPricePer1M: Decimal

    /// Price per 1M output tokens in USD
    public let outputPricePer1M: Decimal

    // MARK: - Initialization

    public init(
        id: String,
        displayName: String,
        vendor: String,
        inputPricePer1M: Decimal,
        outputPricePer1M: Decimal
    ) {
        self.id = id
        self.displayName = displayName
        self.vendor = vendor
        self.inputPricePer1M = inputPricePer1M
        self.outputPricePer1M = outputPricePer1M
    }

    // MARK: - Formatting

    /// Formatted input price (e.g., "$15.00 / 1M")
    public var formattedInputPrice: String {
        BedrockFormatters.formatCurrency(inputPricePer1M) + " / 1M"
    }

    /// Formatted output price (e.g., "$75.00 / 1M")
    public var formattedOutputPrice: String {
        BedrockFormatters.formatCurrency(outputPricePer1M) + " / 1M"
    }
}

// MARK: - BedrockModelUsage

/// Usage data for a single Bedrock model over a time period.
public struct BedrockModelUsage: Sendable, Equatable, Hashable {
    /// The model this usage is for
    public let model: BedrockModel

    /// Number of API invocations
    public let invocations: Int

    /// Total input tokens consumed
    public let inputTokens: Int

    /// Total output tokens generated
    public let outputTokens: Int

    // MARK: - Initialization

    public init(
        model: BedrockModel,
        invocations: Int,
        inputTokens: Int,
        outputTokens: Int
    ) {
        self.model = model
        self.invocations = invocations
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    // MARK: - Cost Calculation

    /// Estimated cost based on model pricing
    public var estimatedCost: Decimal {
        let inputCost = Decimal(inputTokens) / 1_000_000 * model.inputPricePer1M
        let outputCost = Decimal(outputTokens) / 1_000_000 * model.outputPricePer1M
        return inputCost + outputCost
    }

    /// Formatted estimated cost (e.g., "$12.34")
    public var formattedCost: String {
        BedrockFormatters.formatCurrency(estimatedCost)
    }

    // MARK: - Token Formatting

    /// Formatted input tokens (e.g., "1.2M" or "500K")
    public var formattedInputTokens: String {
        BedrockFormatters.formatTokenCount(inputTokens)
    }

    /// Formatted output tokens (e.g., "500K")
    public var formattedOutputTokens: String {
        BedrockFormatters.formatTokenCount(outputTokens)
    }

    /// Formatted total tokens (e.g., "1.7M")
    public var formattedTotalTokens: String {
        BedrockFormatters.formatTokenCount(inputTokens + outputTokens)
    }
}

// MARK: - BedrockUsageSummary

/// Aggregate usage summary across all Bedrock models.
/// This is the primary data structure stored in UsageSnapshot.costUsage-equivalent.
public struct BedrockUsageSummary: Sendable, Equatable {
    /// Usage breakdown by model
    public let modelUsages: [BedrockModelUsage]

    /// The AWS region this data is from
    public let region: String

    /// When this usage data was captured
    public let capturedAt: Date

    /// The time period start for this data
    public let periodStart: Date

    /// The time period end for this data
    public let periodEnd: Date

    /// Daily budget for quota calculations (nil = no budget set)
    public let dailyBudget: Decimal?

    // MARK: - Initialization

    public init(
        modelUsages: [BedrockModelUsage],
        region: String,
        capturedAt: Date = Date(),
        periodStart: Date,
        periodEnd: Date,
        dailyBudget: Decimal? = nil
    ) {
        self.modelUsages = modelUsages
        self.region = region
        self.capturedAt = capturedAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.dailyBudget = dailyBudget
    }

    // MARK: - Aggregate Metrics

    /// Total invocations across all models
    public var totalInvocations: Int {
        modelUsages.reduce(0) { $0 + $1.invocations }
    }

    /// Total input tokens across all models
    public var totalInputTokens: Int {
        modelUsages.reduce(0) { $0 + $1.inputTokens }
    }

    /// Total output tokens across all models
    public var totalOutputTokens: Int {
        modelUsages.reduce(0) { $0 + $1.outputTokens }
    }

    /// Total tokens (input + output)
    public var totalTokens: Int {
        totalInputTokens + totalOutputTokens
    }

    /// Total estimated cost across all models
    public var totalCost: Decimal {
        modelUsages.reduce(Decimal.zero) { $0 + $1.estimatedCost }
    }

    // MARK: - Formatting

    /// Formatted total cost (e.g., "$57.23")
    public var formattedTotalCost: String {
        BedrockFormatters.formatCurrency(totalCost)
    }

    /// Formatted total tokens
    public var formattedTotalTokens: String {
        BedrockFormatters.formatTokenCount(totalTokens)
    }

    /// Formatted daily budget (e.g., "$50.00")
    public var formattedDailyBudget: String? {
        guard let budget = dailyBudget else { return nil }
        return BedrockFormatters.formatCurrency(budget)
    }

    // MARK: - Budget Calculation

    /// Percentage of daily budget used (0-100+)
    public var budgetPercentUsed: Double? {
        guard let budget = dailyBudget, budget > 0 else { return nil }
        let percentage = (totalCost / budget) * 100
        return Double(truncating: percentage as NSDecimalNumber)
    }

    /// Budget status based on percentage used
    public var budgetStatus: BudgetStatus? {
        guard let budget = dailyBudget else { return nil }
        return BudgetStatus.from(cost: totalCost, budget: budget)
    }

    // MARK: - Model Queries

    /// Get usage for a specific model by ID
    public func usage(for modelId: String) -> BedrockModelUsage? {
        modelUsages.first { $0.model.id == modelId }
    }

    /// Models sorted by cost (highest first)
    public var modelsBySpend: [BedrockModelUsage] {
        modelUsages.sorted { $0.estimatedCost > $1.estimatedCost }
    }

    /// Models sorted by invocations (highest first)
    public var modelsByInvocations: [BedrockModelUsage] {
        modelUsages.sorted { $0.invocations > $1.invocations }
    }

    // MARK: - Empty Summary

    /// Creates an empty summary for when no data is available
    public static func empty(region: String) -> BedrockUsageSummary {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        return BedrockUsageSummary(
            modelUsages: [],
            region: region,
            capturedAt: now,
            periodStart: startOfDay,
            periodEnd: now,
            dailyBudget: nil
        )
    }
}
