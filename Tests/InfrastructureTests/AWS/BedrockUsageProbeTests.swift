import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct BedrockUsageProbeTests {

    // MARK: - Mock Settings Repository

    final class MockBedrockSettings: BedrockSettingsRepository, @unchecked Sendable {
        var profileName: String = ""
        var regions: [String] = ["us-east-1"]
        var dailyBudget: Decimal? = nil
        var enabledState: Bool = true

        func awsProfileName() -> String { profileName }
        func setAWSProfileName(_ name: String) { profileName = name }
        func bedrockRegions() -> [String] { regions }
        func setBedrockRegions(_ regions: [String]) { self.regions = regions }
        func bedrockDailyBudget() -> Decimal? { dailyBudget }
        func setBedrockDailyBudget(_ amount: Decimal?) { dailyBudget = amount }
        func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { enabledState }
        func setEnabled(_ enabled: Bool, forProvider id: String) { enabledState = enabled }
    }

    // MARK: - Mock CloudWatch Client

    final class MockCloudWatchClient: BedrockCloudWatchClient, @unchecked Sendable {
        var metricsToReturn: [BedrockMetricData] = []
        var credentialsValid: Bool = true
        var shouldThrowError: Error?

        func fetchBedrockMetrics(region: String, startTime: Date, endTime: Date) async throws -> [BedrockMetricData] {
            if let error = shouldThrowError {
                throw error
            }
            return metricsToReturn
        }

        func verifyCredentials() async -> Bool {
            credentialsValid
        }
    }

    // MARK: - Mock Pricing Service

    final class MockPricingService: BedrockPricingService, @unchecked Sendable {
        var pricingMap: [String: BedrockModel] = [:]
        var shouldThrowError: Error?

        func getModelPricing(modelId: String) async throws -> BedrockModel {
            if let error = shouldThrowError {
                throw error
            }
            if let model = pricingMap[modelId] {
                return model
            }
            // Return default unknown model
            return BedrockModel(
                id: modelId,
                displayName: modelId,
                vendor: "Unknown",
                inputPricePer1M: 0,
                outputPricePer1M: 0
            )
        }
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when credentials are valid`() async {
        let settings = MockBedrockSettings()
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.credentialsValid = true
        let pricing = MockPricingService()

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let available = await probe.isAvailable()
        #expect(available == true)
    }

    @Test
    func `isAvailable returns false when credentials are invalid`() async {
        let settings = MockBedrockSettings()
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.credentialsValid = false
        let pricing = MockPricingService()

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let available = await probe.isAvailable()
        #expect(available == false)
    }

    // MARK: - probe() Tests

    @Test
    func `probe returns empty snapshot when no metrics found`() async throws {
        let settings = MockBedrockSettings()
        settings.regions = ["us-east-1"]
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = []
        let pricing = MockPricingService()

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()
        #expect(snapshot.providerId == "bedrock")
        #expect(snapshot.bedrockUsage != nil)
        #expect(snapshot.bedrockUsage?.modelUsages.isEmpty == true)
        #expect(snapshot.bedrockUsage?.totalCost == 0)
    }

    @Test
    func `probe calculates costs correctly for single model`() async throws {
        let settings = MockBedrockSettings()
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = [
            BedrockMetricData(
                modelId: "anthropic.claude-3-haiku",
                inputTokens: 1_000_000, // 1M input tokens
                outputTokens: 500_000,  // 500K output tokens
                invocations: 100
            )
        ]
        let pricing = MockPricingService()
        pricing.pricingMap["anthropic.claude-3-haiku"] = BedrockModel(
            id: "anthropic.claude-3-haiku",
            displayName: "Claude 3 Haiku",
            vendor: "Anthropic",
            inputPricePer1M: 0.25,  // $0.25 per 1M input
            outputPricePer1M: 1.25  // $1.25 per 1M output
        )

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        // Expected cost: (1M * $0.25/1M) + (0.5M * $1.25/1M) = $0.25 + $0.625 = $0.875
        let expectedCost = Decimal(string: "0.875")!
        #expect(snapshot.bedrockUsage?.totalCost == expectedCost)
        #expect(snapshot.bedrockUsage?.modelUsages.count == 1)
        #expect(snapshot.bedrockUsage?.totalInvocations == 100)
    }

    @Test
    func `probe aggregates multiple models correctly`() async throws {
        let settings = MockBedrockSettings()
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = [
            BedrockMetricData(
                modelId: "anthropic.claude-opus",
                inputTokens: 100_000,
                outputTokens: 50_000,
                invocations: 10
            ),
            BedrockMetricData(
                modelId: "anthropic.claude-haiku",
                inputTokens: 1_000_000,
                outputTokens: 500_000,
                invocations: 100
            )
        ]
        let pricing = MockPricingService()
        pricing.pricingMap["anthropic.claude-opus"] = BedrockModel(
            id: "anthropic.claude-opus",
            displayName: "Claude Opus",
            vendor: "Anthropic",
            inputPricePer1M: 15.00,
            outputPricePer1M: 75.00
        )
        pricing.pricingMap["anthropic.claude-haiku"] = BedrockModel(
            id: "anthropic.claude-haiku",
            displayName: "Claude Haiku",
            vendor: "Anthropic",
            inputPricePer1M: 0.25,
            outputPricePer1M: 1.25
        )

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.bedrockUsage?.modelUsages.count == 2)
        #expect(snapshot.bedrockUsage?.totalInvocations == 110)
        #expect(snapshot.bedrockUsage?.totalInputTokens == 1_100_000)
        #expect(snapshot.bedrockUsage?.totalOutputTokens == 550_000)

        // Opus cost: (0.1M * 15) + (0.05M * 75) = $1.50 + $3.75 = $5.25
        // Haiku cost: (1M * 0.25) + (0.5M * 1.25) = $0.25 + $0.625 = $0.875
        // Total: $6.125
        let expectedTotal = Decimal(string: "6.125")!
        #expect(snapshot.bedrockUsage?.totalCost == expectedTotal)
    }

    @Test
    func `probe skips models with zero usage`() async throws {
        let settings = MockBedrockSettings()
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = [
            BedrockMetricData(
                modelId: "model-with-usage",
                inputTokens: 1000,
                outputTokens: 500,
                invocations: 1
            ),
            BedrockMetricData(
                modelId: "model-with-no-usage",
                inputTokens: 0,
                outputTokens: 0,
                invocations: 0
            )
        ]
        let pricing = MockPricingService()

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()
        #expect(snapshot.bedrockUsage?.modelUsages.count == 1)
    }

    @Test
    func `probe throws error when no regions configured`() async throws {
        let settings = MockBedrockSettings()
        settings.regions = []
        let cloudWatch = MockCloudWatchClient()
        let pricing = MockPricingService()

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    // MARK: - Budget/Quota Tests

    @Test
    func `probe creates quota when daily budget is set`() async throws {
        let settings = MockBedrockSettings()
        settings.dailyBudget = 50 // $50 daily budget
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = [
            BedrockMetricData(
                modelId: "test-model",
                inputTokens: 1_000_000,
                outputTokens: 0,
                invocations: 10
            )
        ]
        let pricing = MockPricingService()
        pricing.pricingMap["test-model"] = BedrockModel(
            id: "test-model",
            displayName: "Test Model",
            vendor: "Test",
            inputPricePer1M: 10.00, // $10 per 1M = $10 cost
            outputPricePer1M: 0
        )

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        // Cost is $10, budget is $50, so 20% used = 80% remaining
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 80.0)
        #expect(snapshot.quotas.first?.quotaType == .modelSpecific("Daily Budget"))
    }

    @Test
    func `probe returns no quota when no budget set`() async throws {
        let settings = MockBedrockSettings()
        settings.dailyBudget = nil
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = [
            BedrockMetricData(
                modelId: "test-model",
                inputTokens: 1000,
                outputTokens: 0,
                invocations: 1
            )
        ]
        let pricing = MockPricingService()

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()
        #expect(snapshot.quotas.isEmpty)
    }

    @Test
    func `probe sorts models by cost descending`() async throws {
        let settings = MockBedrockSettings()
        let cloudWatch = MockCloudWatchClient()
        cloudWatch.metricsToReturn = [
            BedrockMetricData(modelId: "cheap-model", inputTokens: 1000, outputTokens: 0, invocations: 1),
            BedrockMetricData(modelId: "expensive-model", inputTokens: 1000, outputTokens: 0, invocations: 1)
        ]
        let pricing = MockPricingService()
        pricing.pricingMap["cheap-model"] = BedrockModel(
            id: "cheap-model",
            displayName: "Cheap",
            vendor: "Test",
            inputPricePer1M: 1.00,
            outputPricePer1M: 0
        )
        pricing.pricingMap["expensive-model"] = BedrockModel(
            id: "expensive-model",
            displayName: "Expensive",
            vendor: "Test",
            inputPricePer1M: 100.00,
            outputPricePer1M: 0
        )

        let probe = BedrockUsageProbe(
            cloudWatchClient: cloudWatch,
            pricingService: pricing,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()
        let usages = snapshot.bedrockUsage?.modelUsages ?? []

        #expect(usages.count == 2)
        #expect(usages[0].model.id == "expensive-model") // Higher cost first
        #expect(usages[1].model.id == "cheap-model")
    }
}
