import Foundation
import Domain
import Mockable

// MARK: - BedrockUsageProbe

/// Probes AWS Bedrock for usage metrics by querying CloudWatch.
/// Combines CloudWatch metrics with pricing data to calculate costs.
public struct BedrockUsageProbe: UsageProbe {

    private let cloudWatchClient: any BedrockCloudWatchClient
    private let pricingService: any BedrockPricingService
    private let settingsRepository: any BedrockSettingsRepository

    // MARK: - Initialization

    /// Creates a probe with default AWS SDK implementations
    public init(settingsRepository: any BedrockSettingsRepository) {
        let profileName = settingsRepository.awsProfileName()
        self.cloudWatchClient = AWSBedrockCloudWatchClient(profileName: profileName.isEmpty ? nil : profileName)
        self.pricingService = AWSBedrockPricingService()
        self.settingsRepository = settingsRepository
    }

    /// Creates a probe with custom dependencies for testing
    init(
        cloudWatchClient: any BedrockCloudWatchClient,
        pricingService: any BedrockPricingService,
        settingsRepository: any BedrockSettingsRepository
    ) {
        self.cloudWatchClient = cloudWatchClient
        self.pricingService = pricingService
        self.settingsRepository = settingsRepository
    }

    // MARK: - UsageProbe Protocol

    public func isAvailable() async -> Bool {
        // Check if AWS credentials are configured and valid
        await cloudWatchClient.verifyCredentials()
    }

    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.debug("Bedrock probe starting")

        // Get configured regions (or default to us-east-1)
        let regions = settingsRepository.bedrockRegions()
        guard !regions.isEmpty else {
            AppLog.probes.error("Bedrock probe failed: no regions configured")
            throw ProbeError.executionFailed("No AWS regions configured for Bedrock monitoring")
        }

        // Use "today" as the default time period
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        // Aggregate metrics from all configured regions
        var allMetrics: [BedrockMetricData] = []

        for region in regions {
            do {
                let metrics = try await cloudWatchClient.fetchBedrockMetrics(
                    region: region,
                    startTime: startOfDay,
                    endTime: now
                )
                allMetrics.append(contentsOf: metrics)
                AppLog.probes.debug("Fetched \(metrics.count) models from \(region)")
            } catch {
                AppLog.probes.warning("Failed to fetch metrics from \(region): \(error.localizedDescription)")
                // Continue with other regions
            }
        }

        // If no metrics at all, return empty snapshot
        if allMetrics.isEmpty {
            AppLog.probes.info("Bedrock probe: no usage data found")
            return createEmptySnapshot(regions: regions)
        }

        // Convert metrics to domain models with pricing
        let modelUsages = await convertToModelUsages(metrics: allMetrics)

        // Create BedrockUsageSummary
        let summary = BedrockUsageSummary(
            modelUsages: modelUsages,
            region: regions.first ?? "unknown",
            capturedAt: now,
            periodStart: startOfDay,
            periodEnd: now,
            dailyBudget: settingsRepository.bedrockDailyBudget()
        )

        // Create UsageSnapshot with quota based on budget
        let snapshot = createSnapshot(from: summary)

        AppLog.probes.info("Bedrock probe complete: \(modelUsages.count) models, \(summary.formattedTotalCost) total")
        return snapshot
    }

    // MARK: - Internal Helpers (exposed for testing)

    func convertToModelUsages(metrics: [BedrockMetricData]) async -> [BedrockModelUsage] {
        var modelUsages: [BedrockModelUsage] = []

        for metric in metrics {
            // Skip models with zero usage
            guard metric.invocations > 0 || metric.inputTokens > 0 || metric.outputTokens > 0 else {
                continue
            }

            do {
                let model = try await pricingService.getModelPricing(modelId: metric.modelId)
                let usage = BedrockModelUsage(
                    model: model,
                    invocations: metric.invocations,
                    inputTokens: metric.inputTokens,
                    outputTokens: metric.outputTokens
                )
                modelUsages.append(usage)
            } catch {
                AppLog.probes.warning("Could not get pricing for \(metric.modelId): \(error.localizedDescription)")
                // Include usage without pricing (will show $0)
                let unknownModel = BedrockModel(
                    id: metric.modelId,
                    displayName: metric.modelId,
                    vendor: "Unknown",
                    inputPricePer1M: 0,
                    outputPricePer1M: 0
                )
                let usage = BedrockModelUsage(
                    model: unknownModel,
                    invocations: metric.invocations,
                    inputTokens: metric.inputTokens,
                    outputTokens: metric.outputTokens
                )
                modelUsages.append(usage)
            }
        }

        // Sort by cost (highest first)
        return modelUsages.sorted { $0.estimatedCost > $1.estimatedCost }
    }

    func createSnapshot(from summary: BedrockUsageSummary) -> UsageSnapshot {
        // Create quota based on budget status
        var quotas: [UsageQuota] = []

        if summary.budgetStatus != nil,
           let percentUsed = summary.budgetPercentUsed {
            // Convert budget percentage used to percentage remaining
            let percentRemaining = max(0, 100 - percentUsed)

            // Calculate midnight tomorrow using Calendar to handle DST correctly
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)

            let quota = UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: .modelSpecific("Daily Budget"),
                providerId: "bedrock",
                resetsAt: tomorrow
            )
            quotas.append(quota)
        }

        return UsageSnapshot(
            providerId: "bedrock",
            quotas: quotas,
            capturedAt: summary.capturedAt,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil,
            accountTier: nil,
            costUsage: nil,
            bedrockUsage: summary
        )
    }

    private func createEmptySnapshot(regions: [String]) -> UsageSnapshot {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let summary = BedrockUsageSummary(
            modelUsages: [],
            region: regions.first ?? "us-east-1",
            capturedAt: now,
            periodStart: startOfDay,
            periodEnd: now,
            dailyBudget: settingsRepository.bedrockDailyBudget()
        )

        return UsageSnapshot(
            providerId: "bedrock",
            quotas: [],
            capturedAt: now,
            bedrockUsage: summary
        )
    }
}
