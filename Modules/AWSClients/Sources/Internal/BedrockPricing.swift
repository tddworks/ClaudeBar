import Foundation
import AWSPricing
import DataSources
import Diagnostics

// MARK: - BedrockPricingService Protocol

/// Protocol for fetching Bedrock model pricing.
/// Abstracted for testability - production uses AWS Pricing API with caching.
protocol BedrockPricingService: Sendable {
    /// Gets pricing information for a Bedrock model
    /// - Parameter modelId: The AWS Bedrock model ID (`<vendor>.<model>-<date>-v1:0`)
    /// - Returns: BedrockModel with pricing information
    func getModelPricing(modelId: String) async throws -> BedrockModel
}

// MARK: - Default Implementation

/// Production implementation with AWS Pricing API and fallback to bundled defaults
final class AWSBedrockPricingService: BedrockPricingService, @unchecked Sendable {

    /// Cache for model pricing - refreshed daily
    private var cache: [String: BedrockModel] = [:]
    private var cacheDate: Date?
    private let cacheDuration: TimeInterval = 86400 // 24 hours

    /// Lock for thread-safe cache access
    private let lock = NSLock()

    init() {}

    func getModelPricing(modelId: String) async throws -> BedrockModel {
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

        let normalizedId = DefaultBedrockPricing.baseModelId(modelId)

        // Parse model ID format: <vendor>.<model-name>-<date>-v<N>:<variant>
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
        DefaultBedrockPricing.vendor(of: modelId)
    }
}

// MARK: - Pricing Errors

enum PricingError: Error {
    case noPricingFound(String)
    case invalidResponse
}

// MARK: - Default Bundled Pricing

/// The bundled price table, `bedrock-prices.json`: what answers when the
/// Pricing API can't. Data, so a price change edits the file, never Swift
/// (MODULAR_DESIGN §2: no module's Swift names a vendor).
enum DefaultBedrockPricing {

    /// The base model an ID names: an inference profile's prefix dropped.
    /// CloudWatch reports the ID that was called ("global.<vendor>.<model>",
    /// "us.<vendor>.<model>"); prices are kept per base model.
    static func baseModelId(_ modelId: String) -> String {
        modelId.replacingOccurrences(of: "^(global|us|eu|jp|apac|au|ap|sa|ca|me|af)\\.", with: "", options: .regularExpression)
    }

    /// The bundled table's price for `modelId`, nil for a model it doesn't list.
    static func model(for modelId: String) -> BedrockModel? { bundled.model(for: modelId) }

    /// The vendor an ID's first segment names, as the bundled table writes it.
    static func vendor(of modelId: String) -> String { bundled.vendor(of: modelId) }

    /// `bedrock-prices.json`, or an empty table — logged — when it is missing or malformed.
    private static let bundled: Table = {
        do {
            guard let url = Bundle.module.url(forResource: "bedrock-prices", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
        } catch {
            AppLog.probes.error("Bedrock: bundled price table unreadable: \(error.localizedDescription)")
            return Table(vendors: [:], models: [])
        }
    }()

    /// A price table: each model's name and input/output prices per million
    /// tokens, and the vendor names the IDs' first segments stand for.
    struct Table: Decodable {
        struct Row: Decodable {
            let id: String
            let name: String
            let input: Decimal
            let output: Decimal

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
                input = try Self.amount(container, .input)
                output = try Self.amount(container, .output)
            }

            /// `"0.30"`, read as an exact `Decimal` from its text.
            private static func amount(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Decimal {
                let text = try container.decode(String.self, forKey: key)
                guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
                    throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "not an amount: \(text)")
                }
                return value
            }

            private enum CodingKeys: String, CodingKey { case id, name, input, output }
        }

        let vendors: [String: String]
        private let rows: [String: Row]

        init(vendors: [String: String], models: [Row]) {
            self.vendors = vendors
            rows = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(vendors: try container.decodeIfPresent([String: String].self, forKey: .vendors) ?? [:],
                      models: try container.decode([Row].self, forKey: .models))
        }

        init(json: String) throws {
            self = try JSONDecoder().decode(Table.self, from: Data(json.utf8))
        }

        /// The row for `modelId`'s base model, exactly or without its `:N`
        /// version, priced under the ID that was called.
        func model(for modelId: String) -> BedrockModel? {
            let base = DefaultBedrockPricing.baseModelId(modelId)
            let unversioned = base.replacingOccurrences(of: ":\\d+$", with: "", options: .regularExpression)
            guard let row = rows[base] ?? rows[unversioned] else { return nil }
            return BedrockModel(id: modelId, displayName: row.name, vendor: vendor(of: modelId),
                                inputPricePer1M: row.input, outputPricePer1M: row.output)
        }

        /// The vendor `modelId`'s first segment names; unlisted, the segment capitalized.
        func vendor(of modelId: String) -> String {
            guard let segment = DefaultBedrockPricing.baseModelId(modelId).split(separator: ".").first else { return "Unknown" }
            return vendors[segment.lowercased()] ?? String(segment).capitalized
        }

        private enum CodingKeys: String, CodingKey { case vendors, models }
    }
}


/// A Bedrock model's prices, per million tokens.
struct BedrockModel: Sendable, Equatable {
    let id: String
    let displayName: String
    let vendor: String
    let inputPricePer1M: Decimal
    let outputPricePer1M: Decimal
}
