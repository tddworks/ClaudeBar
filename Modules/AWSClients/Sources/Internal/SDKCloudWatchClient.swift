import AWSCloudWatch
import AWSSDKIdentity
import DataSources
import Diagnostics
import Foundation

/// Sums of CloudWatch metrics per dimension value, with the person's own
/// credentials: a named profile (SSO-aware) or the default chain.
struct SDKCloudWatchClient: CloudWatchPort {
    func sums(namespace: String, dimension: String, metrics: [String], region: String, profile: String?,
              from: Date, to: Date) async throws -> [String: [String: Double]] {
        let client = try await Self.client(region: region, profile: profile)
        var values = Set<String>()
        var nextToken: String?
        repeat {
            var input = ListMetricsInput(namespace: namespace)
            input.nextToken = nextToken
            let output = try await client.listMetrics(input: input)
            for metric in output.metrics ?? [] {
                for found in metric.dimensions ?? [] where found.name == dimension {
                    if let value = found.value { values.insert(value) }
                }
            }
            nextToken = output.nextToken
        } while nextToken != nil

        // One data point for the whole range; CloudWatch wants a multiple of 60.
        let period = max(60, ((Int(to.timeIntervalSince(from)) + 59) / 60) * 60)
        var sums: [String: [String: Double]] = [:]
        for value in values.sorted() {
            var row: [String: Double] = [:]
            for metric in metrics {
                let output = try await client.getMetricStatistics(input: GetMetricStatisticsInput(
                    dimensions: [CloudWatchClientTypes.Dimension(name: dimension, value: value)],
                    endTime: to, metricName: metric, namespace: namespace, period: period,
                    startTime: from, statistics: [.sum]))
                row[metric] = output.datapoints?.reduce(0) { $0 + ($1.sum ?? 0) } ?? 0
            }
            sums[value] = row
        }
        AppLog.probes.debug("\(namespace) in \(region): \(sums.count) \(dimension) values")
        return sums
    }

    private static func client(region: String, profile: String?) async throws -> AWSCloudWatch.CloudWatchClient {
        let config = try await AWSCloudWatch.CloudWatchClient.CloudWatchClientConfiguration(region: region)
        if let profile {
            // An SSO profile reads its cached login; a plain one its keys.
            config.awsCredentialIdentityResolver = try SSOAWSCredentialIdentityResolver(profileName: profile)
        }
        return AWSCloudWatch.CloudWatchClient(config: config)
    }
}

/// Bedrock's price list as a `PriceCatalog`: per million tokens, as exact
/// decimal texts, with the model's name and vendor.
struct SDKPriceCatalog: PriceCatalog {
    let pricing: any BedrockPricingService

    func prices(service: String, ids: [String]) async -> [String: [String: String]] {
        guard service == "AmazonBedrock" else { return [:] }
        var prices: [String: [String: String]] = [:]
        for id in ids {
            guard let model = try? await pricing.getModelPricing(modelId: id) else { continue }
            prices[id] = ["input": "\(model.inputPricePer1M)", "output": "\(model.outputPricePer1M)", "per": "1000000",
                          "name": model.displayName, "vendor": model.vendor]
        }
        return prices
    }
}
