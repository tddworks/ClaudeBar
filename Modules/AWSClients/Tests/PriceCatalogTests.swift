import Foundation
import Testing
@testable import AWSClients

/// Bedrock's price list as a `PriceCatalog`: exact per-million prices, the
/// model's name and vendor, and the bundled table when the API can't answer.
@Suite
struct PriceCatalogTests {
    struct Prices: BedrockPricingService {
        let models: [String: BedrockModel]
        func getModelPricing(modelId: String) async throws -> BedrockModel {
            guard let model = models[modelId] else { throw PricingError.noPricingFound(modelId) }
            return model
        }
    }

    @Test func `a model's prices come back as exact texts per million tokens`() async {
        let catalog = SDKPriceCatalog(pricing: Prices(models: [
            "anthropic.claude-sonnet-4": BedrockModel(id: "anthropic.claude-sonnet-4", displayName: "Claude Sonnet 4", vendor: "Anthropic",
                                                      inputPricePer1M: Decimal(string: "3.00")!, outputPricePer1M: 15),
        ]))
        let prices = await catalog.prices(service: "AmazonBedrock", ids: ["anthropic.claude-sonnet-4", "acme.unknown"])
        #expect(prices["anthropic.claude-sonnet-4"] == ["input": "3", "output": "15", "per": "1000000", "name": "Claude Sonnet 4", "vendor": "Anthropic"])
        #expect(prices["acme.unknown"] == nil)
    }

    @Test func `another service has no prices here`() async {
        #expect(await SDKPriceCatalog(pricing: Prices(models: [:])).prices(service: "AmazonEC2", ids: ["x"]).isEmpty)
    }

    @Test func `the bundled table knows a cross-region model by its base id`() throws {
        let regional = try #require(DefaultBedrockPricing.model(for: "us.anthropic.claude-opus-4-5-20251101-v1:0"))
        let base = try #require(DefaultBedrockPricing.model(for: "anthropic.claude-opus-4-5-20251101-v1:0"))
        #expect(regional.inputPricePer1M == base.inputPricePer1M)
        #expect(regional.outputPricePer1M == base.outputPricePer1M)
        #expect(regional.inputPricePer1M > 0)
    }
}
