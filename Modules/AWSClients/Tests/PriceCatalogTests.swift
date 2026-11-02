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

    @Test func `should give exact price texts per million tokens, and none for an unknown model`() async {
        let catalog = SDKPriceCatalog(pricing: Prices(models: [
            "anthropic.claude-sonnet-4": BedrockModel(id: "anthropic.claude-sonnet-4", displayName: "Claude Sonnet 4", vendor: "Anthropic",
                                                      inputPricePer1M: Decimal(string: "3.00")!, outputPricePer1M: 15),
        ]))
        let prices = await catalog.prices(service: "AmazonBedrock", ids: ["anthropic.claude-sonnet-4", "acme.unknown"])
        #expect(prices["anthropic.claude-sonnet-4"] == ["input": "3", "output": "15", "per": "1000000", "name": "Claude Sonnet 4", "vendor": "Anthropic"])
        #expect(prices["acme.unknown"] == nil)
    }

    @Test func `should have no prices for a service other than Bedrock`() async {
        #expect(await SDKPriceCatalog(pricing: Prices(models: [:])).prices(service: "AmazonEC2", ids: ["x"]).isEmpty)
    }

    @Test(arguments: ["global", "us", "eu", "jp", "apac", "au"])
    func `should price an inference profile like its base model in the bundled price table`(_ profile: String) throws {
        let routed = try #require(DefaultBedrockPricing.model(for: "\(profile).anthropic.claude-opus-4-5-20251101-v1:0"))
        #expect(routed.id == "\(profile).anthropic.claude-opus-4-5-20251101-v1:0")
        #expect(routed.displayName == "Claude Opus 4.5")
        #expect(routed.inputPricePer1M == 5)
        #expect(routed.outputPricePer1M == 25)
    }

    @Test(arguments: [
        ("anthropic.claude-fable-5-1", "Claude Fable 5.1", "10", "50"),
        ("anthropic.claude-fable-5", "Claude Fable 5", "10", "50"),
        ("anthropic.claude-opus-5-5", "Claude Opus 5.5", "4", "20"),
        ("anthropic.claude-opus-5", "Claude Opus 5", "5", "25"),
        ("anthropic.claude-sonnet-5-5", "Claude Sonnet 5.5", "2", "10"),
        ("anthropic.claude-sonnet-5", "Claude Sonnet 5", "2", "10"),
        ("anthropic.claude-haiku-5-5", "Claude Haiku 5.5", "0.10", "0.50"),
        ("anthropic.claude-opus-4-8", "Claude Opus 4.8", "5", "25"),
        ("anthropic.claude-opus-4-7", "Claude Opus 4.7", "5", "25"),
        ("anthropic.claude-opus-4-6-v1", "Claude Opus 4.6", "5", "25"),
        ("anthropic.claude-sonnet-4-6", "Claude Sonnet 4.6", "3", "15"),
        ("anthropic.claude-mythos-5-1", "Claude Mythos 5.1", "10", "50"),
        ("anthropic.claude-sonnet-4-5-20250929-v1:0", "Claude Sonnet 4.5", "3", "15"),
        ("anthropic.claude-opus-4-5-20251101-v1:0", "Claude Opus 4.5", "5", "25"),
        ("anthropic.claude-haiku-4-5-20251001-v1:0", "Claude Haiku 4.5", "1", "5"),
        ("anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4", "3", "15"),
    ])
    func `should price Claude at Bedrock's global prices when the price list can't answer`(
        _ id: String, _ name: String, _ input: String, _ output: String) throws {
        for modelId in [id, "global.\(id)"] {
            let model = try #require(DefaultBedrockPricing.model(for: modelId))
            #expect(model.displayName == name)
            #expect(model.vendor == "Anthropic")
            #expect(model.inputPricePer1M == Decimal(string: input)!)
            #expect(model.outputPricePer1M == Decimal(string: output)!)
        }
    }

    /// AWS lists no global price for these: their on-demand regional price.
    @Test(arguments: [
        ("anthropic.claude-mythos-5", "Claude Mythos 5", "11", "55"),
        ("anthropic.claude-mythos-preview", "Claude Mythos Preview", "27.50", "137.50"),
        ("anthropic.claude-opus-4-1-20250805-v1:0", "Claude Opus 4.1", "15", "75"),
        ("anthropic.claude-opus-4-20250514-v1:0", "Claude Opus 4", "15", "75"),
        ("anthropic.claude-3-7-sonnet-20250219-v1:0", "Claude 3.7 Sonnet", "3", "15"),
    ])
    func `should price a Claude model with no global price at Bedrock's regional on-demand price`(
        _ id: String, _ name: String, _ input: String, _ output: String) throws {
        for modelId in [id, "us.\(id)"] {
            let model = try #require(DefaultBedrockPricing.model(for: modelId))
            #expect(model.displayName == name)
            #expect(model.vendor == "Anthropic")
            #expect(model.inputPricePer1M == Decimal(string: input)!)
            #expect(model.outputPricePer1M == Decimal(string: output)!)
        }
    }
}

@Suite struct ProfileResolutionTests {
    @Test func `should resolve a named static profile without requiring SSO`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config"), credentials = root.appendingPathComponent("credentials")
        try Data("".utf8).write(to: config)
        try Data("[default]\naws_access_key_id = fake-personal\naws_secret_access_key = fake-personal-secret\n[work]\naws_access_key_id = fake-work\naws_secret_access_key = fake-work-secret\n".utf8).write(to: credentials)
        let selected = try await SDKCloudWatchClient.configuration(region: "us-east-1", profile: "work",
            configFilePath: config.path, credentialsFilePath: credentials.path)
        let identity = try await selected.awsCredentialIdentityResolver.getIdentity(identityProperties: nil)
        #expect(identity.accessKey == "fake-work")
        #expect(identity.secret == "fake-work-secret")
        let missing = try await SDKCloudWatchClient.configuration(region: "us-east-1", profile: "missing",
            configFilePath: config.path, credentialsFilePath: credentials.path)
        await #expect(throws: (any Error).self) { try await missing.awsCredentialIdentityResolver.getIdentity(identityProperties: nil) }
    }
}
