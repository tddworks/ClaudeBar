import Foundation
import Domain

/// Demo probe for Z.ai that returns mock data for testing the UI.
/// Useful when users don't have z.ai credentials but want to preview the provider.
public struct ZaiDemoUsageProbe: UsageProbe {

    /// Sample response matching the format from z.ai API
    private static let sampleQuotaLimitResponse = """
    {
      "data": {
        "limits": [
          {
            "type": "TOKENS_LIMIT",
            "percentage": 65
          },
          {
            "type": "TIME_LIMIT",
            "percentage": 30,
            "currentValue": 100,
            "usage": 3600,
            "usageDetails": []
          }
        ]
      }
    }
    """

    public init() {}

    // MARK: - UsageProbe

    /// Demo mode is always available
    public func isAvailable() async -> Bool {
        true
    }

    /// Returns mock usage data for UI testing
    public func probe() async throws -> UsageSnapshot {
        AppLog.probes.info("Z.ai demo probe: returning mock data")

        let data = Data(Self.sampleQuotaLimitResponse.utf8)
        return try ZaiUsageProbe.parseQuotaLimitResponse(data, providerId: "zai")
    }
}