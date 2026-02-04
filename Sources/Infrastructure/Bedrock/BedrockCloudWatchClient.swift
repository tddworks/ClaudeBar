import Foundation
import AWSCloudWatch
import AWSSDKIdentity
import Mockable
import Domain

// MARK: - CloudWatch Metric Data

/// Represents raw metric data from CloudWatch for a single model
public struct BedrockMetricData: Sendable, Equatable {
    public let modelId: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let invocations: Int

    public init(modelId: String, inputTokens: Int, outputTokens: Int, invocations: Int) {
        self.modelId = modelId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.invocations = invocations
    }
}

// MARK: - BedrockCloudWatchClient Protocol

/// Protocol for fetching Bedrock usage metrics from CloudWatch.
/// Abstracted for testability - production uses AWSCloudWatchClient.
@Mockable
public protocol BedrockCloudWatchClient: Sendable {
    /// Fetches Bedrock usage metrics for the specified time period
    /// - Parameters:
    ///   - region: AWS region to query
    ///   - startTime: Start of the time period
    ///   - endTime: End of the time period
    /// - Returns: Array of metric data per model
    func fetchBedrockMetrics(
        region: String,
        startTime: Date,
        endTime: Date
    ) async throws -> [BedrockMetricData]

    /// Verifies AWS credentials are valid
    /// - Returns: True if credentials can authenticate successfully
    func verifyCredentials() async -> Bool
}

// MARK: - Default Implementation

/// Production implementation using AWS SDK CloudWatch client
public final class AWSBedrockCloudWatchClient: BedrockCloudWatchClient, @unchecked Sendable {

    private let profileName: String?

    public init(profileName: String? = nil) {
        self.profileName = profileName
    }

    public func fetchBedrockMetrics(
        region: String,
        startTime: Date,
        endTime: Date
    ) async throws -> [BedrockMetricData] {
        // Build CloudWatch client for the specified region
        let client = try await buildClient(region: region)

        // Get list of models by querying for Invocations metric with ModelId dimension
        let modelIds = try await listBedrockModels(client: client, startTime: startTime, endTime: endTime)

        // Fetch metrics for each model
        var results: [BedrockMetricData] = []
        for modelId in modelIds {
            let metrics = try await fetchMetricsForModel(
                client: client,
                modelId: modelId,
                startTime: startTime,
                endTime: endTime
            )
            results.append(metrics)
        }

        return results
    }

    public func verifyCredentials() async -> Bool {
        do {
            // Try to create a client and make a simple call
            let client = try await buildClient(region: "us-east-1")
            // List metrics is a cheap call to verify credentials work
            let input = ListMetricsInput(namespace: "AWS/Bedrock")
            _ = try await client.listMetrics(input: input)
            return true
        } catch {
            AppLog.probes.warning("AWS credential verification failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func buildClient(region: String) async throws -> CloudWatchClient {
        // If profile name is specified, set AWS_PROFILE environment variable
        // This is needed because when running from Xcode, env vars aren't inherited
        if let profile = profileName, !profile.isEmpty {
            setenv("AWS_PROFILE", profile, 1)
            // Also ensure HOME is set for the SDK to find ~/.aws/
            if getenv("HOME") == nil {
                setenv("HOME", NSHomeDirectory(), 1)
            }
            AppLog.probes.debug("Using AWS profile: \(profile)")
        }

        // Try to create client with SSO-aware credential chain
        do {
            // Create configuration - the SDK's default chain should respect AWS_PROFILE
            let config = try await CloudWatchClient.CloudWatchClientConfiguration(region: region)

            // Use SSO credential resolver when a profile is specified
            // The SSO resolver reads the profile's SSO configuration and uses cached tokens
            if let profile = profileName, !profile.isEmpty {
                AppLog.probes.debug("Creating SSOAWSCredentialIdentityResolver for profile: \(profile)")
                let ssoResolver = try SSOAWSCredentialIdentityResolver(profileName: profile)
                config.awsCredentialIdentityResolver = ssoResolver
            }

            return CloudWatchClient(config: config)
        } catch {
            AppLog.probes.error("Failed to create CloudWatch client: \(error)")
            throw error
        }
    }

    private func listBedrockModels(
        client: CloudWatchClient,
        startTime: Date,
        endTime: Date
    ) async throws -> [String] {
        // Query CloudWatch for all unique ModelId values
        // Use simple query without filters that might cause InvalidParameterValueException
        AppLog.probes.debug("Listing Bedrock models from CloudWatch...")

        let input = ListMetricsInput(
            namespace: "AWS/Bedrock"
        )

        var modelIds: Set<String> = []
        var nextToken: String? = nil

        repeat {
            var paginatedInput = input
            paginatedInput.nextToken = nextToken

            let output = try await client.listMetrics(input: paginatedInput)
            AppLog.probes.debug("Got \(output.metrics?.count ?? 0) metrics from CloudWatch")

            for metric in output.metrics ?? [] {
                if let dimensions = metric.dimensions {
                    for dimension in dimensions {
                        if dimension.name == "ModelId", let value = dimension.value {
                            modelIds.insert(value)
                        }
                    }
                }
            }

            nextToken = output.nextToken
        } while nextToken != nil

        AppLog.probes.debug("Found \(modelIds.count) unique models: \(Array(modelIds).joined(separator: ", "))")
        return Array(modelIds)
    }

    private func fetchMetricsForModel(
        client: CloudWatchClient,
        modelId: String,
        startTime: Date,
        endTime: Date
    ) async throws -> BedrockMetricData {
        // Calculate period - we want a single data point for the entire range
        // CloudWatch requires period to be a multiple of 60 for periods >= 60 seconds
        let rawPeriod = Int(endTime.timeIntervalSince(startTime))
        let periodSeconds = max(60, ((rawPeriod + 59) / 60) * 60) // Round up to nearest 60

        let modelDimension = CloudWatchClientTypes.Dimension(name: "ModelId", value: modelId)

        // Fetch metrics sequentially to avoid data race with non-Sendable client
        let inputTokens = try await fetchMetricSum(
            client: client,
            metricName: "InputTokenCount",
            dimensions: [modelDimension],
            startTime: startTime,
            endTime: endTime,
            period: periodSeconds
        )

        let outputTokens = try await fetchMetricSum(
            client: client,
            metricName: "OutputTokenCount",
            dimensions: [modelDimension],
            startTime: startTime,
            endTime: endTime,
            period: periodSeconds
        )

        let invocations = try await fetchMetricSum(
            client: client,
            metricName: "Invocations",
            dimensions: [modelDimension],
            startTime: startTime,
            endTime: endTime,
            period: periodSeconds
        )

        return BedrockMetricData(
            modelId: modelId,
            inputTokens: Int(inputTokens),
            outputTokens: Int(outputTokens),
            invocations: Int(invocations)
        )
    }

    private func fetchMetricSum(
        client: CloudWatchClient,
        metricName: String,
        dimensions: [CloudWatchClientTypes.Dimension],
        startTime: Date,
        endTime: Date,
        period: Int
    ) async throws -> Double {
        let input = GetMetricStatisticsInput(
            dimensions: dimensions,
            endTime: endTime,
            metricName: metricName,
            namespace: "AWS/Bedrock",
            period: period,
            startTime: startTime,
            statistics: [.sum]
        )

        let output = try await client.getMetricStatistics(input: input)

        // Sum up all datapoints (should be just one with our period setting)
        let total = output.datapoints?.reduce(0.0) { $0 + ($1.sum ?? 0) } ?? 0
        return total
    }
}
