import Foundation
import AWSPricing
import Mockable
import Domain

// MARK: - BedrockPricingService Protocol

/// Protocol for fetching Bedrock model pricing.
/// Abstracted for testability - production uses AWS Pricing API with caching.
@Mockable
public protocol BedrockPricingService: Sendable {
    /// Gets pricing information for a Bedrock model
    /// - Parameter modelId: The AWS Bedrock model ID (e.g., "anthropic.claude-opus-4-5-20251101-v1:0")
    /// - Returns: BedrockModel with pricing information
    func getModelPricing(modelId: String) async throws -> BedrockModel
}

// MARK: - Default Implementation

/// Production implementation with AWS Pricing API and fallback to bundled defaults
public final class AWSBedrockPricingService: BedrockPricingService, @unchecked Sendable {

    /// Cache for model pricing - refreshed daily
    private var cache: [String: BedrockModel] = [:]
    private var cacheDate: Date?
    private let cacheDuration: TimeInterval = 86400 // 24 hours

    /// Lock for thread-safe cache access
    private let lock = NSLock()

    public init() {}

    public func getModelPricing(modelId: String) async throws -> BedrockModel {
        // Check cache first
        if let cached = getCachedModel(modelId) {
            return cached
        }

        // Try to fetch from AWS Pricing API
        do {
            let model = try await fetchPricingFromAPI(modelId: modelId)
            cacheModel(model)
            return model
        } catch {
            AppLog.probes.info("AWS Pricing API unavailable, using bundled defaults: \(error.localizedDescription)")
            // Fall back to bundled defaults
            if let defaultModel = DefaultBedrockPricing.model(for: modelId) {
                return defaultModel
            }
            // Create unknown model with zero pricing (will show as model with no cost data)
            return BedrockModel(
                id: modelId,
                displayName: extractDisplayName(from: modelId),
                vendor: extractVendor(from: modelId),
                inputPricePer1M: 0,
                outputPricePer1M: 0
            )
        }
    }

    // MARK: - Cache Management

    private func getCachedModel(_ modelId: String) -> BedrockModel? {
        lock.lock()
        defer { lock.unlock() }

        // Check if cache is stale
        if let cacheDate, Date().timeIntervalSince(cacheDate) > cacheDuration {
            cache.removeAll()
            self.cacheDate = nil
            return nil
        }

        return cache[modelId]
    }

    private func cacheModel(_ model: BedrockModel) {
        lock.lock()
        defer { lock.unlock() }

        cache[model.id] = model
        if cacheDate == nil {
            cacheDate = Date()
        }
    }

    // MARK: - AWS Pricing API

    private func fetchPricingFromAPI(modelId: String) async throws -> BedrockModel {
        // AWS Pricing API is only available in us-east-1 and ap-south-1
        let client = try await PricingClient(region: "us-east-1")

        // Query for Bedrock pricing
        // The filter format for Bedrock is specific to the service
        let filters = [
            PricingClientTypes.Filter(
                field: "ServiceCode",
                type: .termMatch,
                value: "AmazonBedrock"
            ),
            PricingClientTypes.Filter(
                field: "modelId",
                type: .termMatch,
                value: modelId
            )
        ]

        let input = GetProductsInput(
            filters: filters,
            maxResults: 10,
            serviceCode: "AmazonBedrock"
        )

        let output = try await client.getProducts(input: input)

        // Parse pricing from response
        guard let priceList = output.priceList, !priceList.isEmpty else {
            throw PricingError.noPricingFound(modelId)
        }

        // Parse the JSON pricing data
        return try parsePricingResponse(priceList.first!, modelId: modelId)
    }

    private func parsePricingResponse(_ jsonString: String, modelId: String) throws -> BedrockModel {
        guard let data = jsonString.data(using: .utf8) else {
            throw PricingError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Extract pricing terms
        guard let terms = json?["terms"] as? [String: Any],
              let onDemand = terms["OnDemand"] as? [String: Any] else {
            throw PricingError.invalidResponse
        }

        // Navigate the nested structure to find input/output token prices
        var inputPrice: Decimal = 0
        var outputPrice: Decimal = 0

        for (_, termData) in onDemand {
            guard let term = termData as? [String: Any],
                  let priceDimensions = term["priceDimensions"] as? [String: Any] else {
                continue
            }

            for (_, dimension) in priceDimensions {
                guard let dim = dimension as? [String: Any],
                      let pricePerUnit = dim["pricePerUnit"] as? [String: Any],
                      let usdString = pricePerUnit["USD"] as? String,
                      let description = dim["description"] as? String else {
                    continue
                }

                let rawPrice = Decimal(string: usdString) ?? 0
                let unit = (dim["unit"] as? String)?.lowercased() ?? ""

                // Convert price to per-1M tokens based on unit field
                let pricePer1M: Decimal
                if unit.contains("1m") || unit.contains("million") {
                    // Already per 1M tokens
                    pricePer1M = rawPrice
                } else if unit.contains("1k") || unit.contains("thousand") {
                    // Per 1K tokens - multiply by 1000
                    pricePer1M = rawPrice * 1000
                } else {
                    // Assume per token - multiply by 1M
                    pricePer1M = rawPrice * 1_000_000
                }

                // Determine if this is input or output pricing based on description
                if description.lowercased().contains("input") {
                    inputPrice = pricePer1M
                } else if description.lowercased().contains("output") {
                    outputPrice = pricePer1M
                }
            }
        }

        return BedrockModel(
            id: modelId,
            displayName: extractDisplayName(from: modelId),
            vendor: extractVendor(from: modelId),
            inputPricePer1M: inputPrice,
            outputPricePer1M: outputPrice
        )
    }

    // MARK: - Model Name Extraction

    private func extractDisplayName(from modelId: String) -> String {
        // Check bundled defaults first
        if let model = DefaultBedrockPricing.model(for: modelId) {
            return model.displayName
        }

        // Normalize: strip regional prefix (us., eu., etc.) for cross-region inference
        let normalizedId = modelId.replacingOccurrences(
            of: "^(us|eu|ap|sa|ca|me|af)\\.",
            with: "",
            options: .regularExpression
        )

        // Parse model ID format: provider.model-name-version:variant
        // e.g., "anthropic.claude-opus-4-5-20251101-v1:0"
        let parts = normalizedId.split(separator: ".")
        guard parts.count >= 2 else { return modelId }

        let modelPart = String(parts[1])
        // Remove version suffix and variant
        let cleanName = modelPart
            .replacingOccurrences(of: "-v\\d+:\\d+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-\\d{8}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: " ")
            .capitalized

        return cleanName
    }

    private func extractVendor(from modelId: String) -> String {
        // Normalize: strip regional prefix (us., eu., etc.) for cross-region inference
        let normalizedId = modelId.replacingOccurrences(
            of: "^(us|eu|ap|sa|ca|me|af)\\.",
            with: "",
            options: .regularExpression
        )

        let parts = normalizedId.split(separator: ".")
        guard let vendor = parts.first else { return "Unknown" }

        switch vendor.lowercased() {
        case "anthropic": return "Anthropic"
        case "amazon": return "Amazon"
        case "meta": return "Meta"
        case "mistral": return "Mistral AI"
        case "cohere": return "Cohere"
        case "ai21": return "AI21 Labs"
        case "stability": return "Stability AI"
        default: return String(vendor).capitalized
        }
    }
}

// MARK: - Pricing Errors

enum PricingError: Error {
    case noPricingFound(String)
    case invalidResponse
}

// MARK: - Default Bundled Pricing

/// Bundled default pricing for common Bedrock models
/// Updated periodically - serves as fallback when Pricing API is unavailable
public enum DefaultBedrockPricing {

    /// Returns bundled pricing for known models, nil for unknown models
    public static func model(for modelId: String) -> BedrockModel? {
        // Normalize model ID: strip regional prefix (us., eu., ap., etc.) for cross-region inference
        // CloudWatch returns "us.anthropic.claude-..." but pricing uses "anthropic.claude-..."
        let normalizedId = modelId.replacingOccurrences(
            of: "^(us|eu|ap|sa|ca|me|af)\\.",
            with: "",
            options: .regularExpression
        )

        // Check exact match first (with normalized ID)
        if let model = models[normalizedId] {
            return BedrockModel(
                id: modelId, // Preserve original ID with regional prefix
                displayName: model.displayName,
                vendor: model.vendor,
                inputPricePer1M: model.inputPricePer1M,
                outputPricePer1M: model.outputPricePer1M
            )
        }

        // Check partial match (without version suffix)
        let baseModelId = normalizedId.replacingOccurrences(of: ":\\d+$", with: "", options: .regularExpression)
        if let model = models[baseModelId] {
            return BedrockModel(
                id: modelId, // Preserve original ID
                displayName: model.displayName,
                vendor: model.vendor,
                inputPricePer1M: model.inputPricePer1M,
                outputPricePer1M: model.outputPricePer1M
            )
        }

        return nil
    }

    private static let models: [String: BedrockModel] = [
        // Anthropic Claude models (as of Jan 2025)
        "anthropic.claude-opus-4-5-20251101-v1:0": BedrockModel(
            id: "anthropic.claude-opus-4-5-20251101-v1:0",
            displayName: "Claude Opus 4.5",
            vendor: "Anthropic",
            inputPricePer1M: 15.00,
            outputPricePer1M: 75.00
        ),
        "anthropic.claude-haiku-4-5-20251001-v1:0": BedrockModel(
            id: "anthropic.claude-haiku-4-5-20251001-v1:0",
            displayName: "Claude Haiku 4.5",
            vendor: "Anthropic",
            inputPricePer1M: 1.00,
            outputPricePer1M: 5.00
        ),
        "anthropic.claude-sonnet-4-20250514-v1:0": BedrockModel(
            id: "anthropic.claude-sonnet-4-20250514-v1:0",
            displayName: "Claude Sonnet 4",
            vendor: "Anthropic",
            inputPricePer1M: 3.00,
            outputPricePer1M: 15.00
        ),
        "anthropic.claude-3-5-sonnet-20241022-v2:0": BedrockModel(
            id: "anthropic.claude-3-5-sonnet-20241022-v2:0",
            displayName: "Claude 3.5 Sonnet v2",
            vendor: "Anthropic",
            inputPricePer1M: 3.00,
            outputPricePer1M: 15.00
        ),
        "anthropic.claude-3-5-sonnet-20240620-v1:0": BedrockModel(
            id: "anthropic.claude-3-5-sonnet-20240620-v1:0",
            displayName: "Claude 3.5 Sonnet",
            vendor: "Anthropic",
            inputPricePer1M: 3.00,
            outputPricePer1M: 15.00
        ),
        "anthropic.claude-3-5-haiku-20241022-v1:0": BedrockModel(
            id: "anthropic.claude-3-5-haiku-20241022-v1:0",
            displayName: "Claude 3.5 Haiku",
            vendor: "Anthropic",
            inputPricePer1M: 0.80,
            outputPricePer1M: 4.00
        ),
        "anthropic.claude-3-opus-20240229-v1:0": BedrockModel(
            id: "anthropic.claude-3-opus-20240229-v1:0",
            displayName: "Claude 3 Opus",
            vendor: "Anthropic",
            inputPricePer1M: 15.00,
            outputPricePer1M: 75.00
        ),
        "anthropic.claude-3-sonnet-20240229-v1:0": BedrockModel(
            id: "anthropic.claude-3-sonnet-20240229-v1:0",
            displayName: "Claude 3 Sonnet",
            vendor: "Anthropic",
            inputPricePer1M: 3.00,
            outputPricePer1M: 15.00
        ),
        "anthropic.claude-3-haiku-20240307-v1:0": BedrockModel(
            id: "anthropic.claude-3-haiku-20240307-v1:0",
            displayName: "Claude 3 Haiku",
            vendor: "Anthropic",
            inputPricePer1M: 0.25,
            outputPricePer1M: 1.25
        ),

        // Amazon Titan models
        "amazon.titan-text-premier-v1:0": BedrockModel(
            id: "amazon.titan-text-premier-v1:0",
            displayName: "Titan Text Premier",
            vendor: "Amazon",
            inputPricePer1M: 0.50,
            outputPricePer1M: 1.50
        ),
        "amazon.titan-text-express-v1": BedrockModel(
            id: "amazon.titan-text-express-v1",
            displayName: "Titan Text Express",
            vendor: "Amazon",
            inputPricePer1M: 0.20,
            outputPricePer1M: 0.60
        ),
        "amazon.titan-text-lite-v1": BedrockModel(
            id: "amazon.titan-text-lite-v1",
            displayName: "Titan Text Lite",
            vendor: "Amazon",
            inputPricePer1M: 0.15,
            outputPricePer1M: 0.20
        ),

        // Meta Llama models
        "meta.llama3-2-90b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-2-90b-instruct-v1:0",
            displayName: "Llama 3.2 90B",
            vendor: "Meta",
            inputPricePer1M: 0.72,
            outputPricePer1M: 0.72
        ),
        "meta.llama3-2-11b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-2-11b-instruct-v1:0",
            displayName: "Llama 3.2 11B",
            vendor: "Meta",
            inputPricePer1M: 0.16,
            outputPricePer1M: 0.16
        ),
        "meta.llama3-2-3b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-2-3b-instruct-v1:0",
            displayName: "Llama 3.2 3B",
            vendor: "Meta",
            inputPricePer1M: 0.10,
            outputPricePer1M: 0.10
        ),
        "meta.llama3-2-1b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-2-1b-instruct-v1:0",
            displayName: "Llama 3.2 1B",
            vendor: "Meta",
            inputPricePer1M: 0.10,
            outputPricePer1M: 0.10
        ),
        "meta.llama3-1-405b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-1-405b-instruct-v1:0",
            displayName: "Llama 3.1 405B",
            vendor: "Meta",
            inputPricePer1M: 2.40,
            outputPricePer1M: 2.40
        ),
        "meta.llama3-1-70b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-1-70b-instruct-v1:0",
            displayName: "Llama 3.1 70B",
            vendor: "Meta",
            inputPricePer1M: 0.72,
            outputPricePer1M: 0.72
        ),
        "meta.llama3-1-8b-instruct-v1:0": BedrockModel(
            id: "meta.llama3-1-8b-instruct-v1:0",
            displayName: "Llama 3.1 8B",
            vendor: "Meta",
            inputPricePer1M: 0.22,
            outputPricePer1M: 0.22
        ),

        // Mistral models
        "mistral.mistral-large-2407-v1:0": BedrockModel(
            id: "mistral.mistral-large-2407-v1:0",
            displayName: "Mistral Large",
            vendor: "Mistral AI",
            inputPricePer1M: 3.00,
            outputPricePer1M: 9.00
        ),
        "mistral.mistral-small-2402-v1:0": BedrockModel(
            id: "mistral.mistral-small-2402-v1:0",
            displayName: "Mistral Small",
            vendor: "Mistral AI",
            inputPricePer1M: 0.10,
            outputPricePer1M: 0.30
        ),
        "mistral.mixtral-8x7b-instruct-v0:1": BedrockModel(
            id: "mistral.mixtral-8x7b-instruct-v0:1",
            displayName: "Mixtral 8x7B",
            vendor: "Mistral AI",
            inputPricePer1M: 0.45,
            outputPricePer1M: 0.70
        ),
    ]
}
