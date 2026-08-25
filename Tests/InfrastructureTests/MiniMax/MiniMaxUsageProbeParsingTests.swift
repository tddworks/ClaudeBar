import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct MiniMaxUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleSuccessResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    static let sampleTokenPlanResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "general",
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "current_interval_remaining_percent": 100,
          "current_weekly_remaining_percent": 98,
          "start_time": 1787673600000,
          "end_time": 1787691600000,
          "weekly_start_time": 1787500800000,
          "weekly_end_time": 1788105600000
        },
        {
          "model_name": "video",
          "current_interval_total_count": 0,
          "current_interval_usage_count": 0,
          "current_interval_remaining_percent": 100,
          "current_weekly_remaining_percent": 100,
          "start_time": 1787673600000,
          "end_time": 1787760000000,
          "weekly_start_time": 1787500800000,
          "weekly_end_time": 1788105600000
        }
      ]
    }
    """

    static let sampleMultiModelResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1500,
          "current_interval_usage_count": 255,
          "remains_time": 1234,
          "end_time": 1735689600000
        },
        {
          "model_name": "minimax-m1",
          "current_interval_total_count": 500,
          "current_interval_usage_count": 400,
          "remains_time": 1234,
          "end_time": 1735689600000
        }
      ]
    }
    """

    static let sampleErrorResponse = """
    {
      "base_resp": { "status_code": 1001, "status_msg": "invalid api key" },
      "model_remains": []
    }
    """

    static let sampleEmptyRemainsResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": []
    }
    """

    static let sampleNoEndTimeResponse = """
    {
      "base_resp": { "status_code": 0, "status_msg": "success" },
      "model_remains": [
        {
          "model_name": "minimax-m2",
          "current_interval_total_count": 1000,
          "current_interval_usage_count": 500
        }
      ]
    }
    """

    // MARK: - Parsing Tests

    @Test
    func `parses model_remains into UsageQuota`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("minimax-m2"))
        #expect(snapshot.providerId == "minimax")
    }

    @Test
    func `maps percentage correctly`() throws {
        // Given: usage_count=255 is actually REMAINING (not used) → 255/1500 = 17%
        // MiniMax API naming is misleading - see probe comment for details
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // Then
        let expected = Double(255) / Double(1500) * 100.0
        #expect(snapshot.quotas[0].percentRemaining == expected)
    }

    @Test
    func `uses token plan remaining percentages when count totals are zero`() throws {
        let data = Data(Self.sampleTokenPlanResponse.utf8)

        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas[0].percentRemaining == 98)
        #expect(snapshot.quotas[0].resetText == "2% used")
        #expect(snapshot.quotas[0].windowDuration == 604_800.0)
        #expect(snapshot.quotas[1].percentRemaining == 100)
    }

    @Test
    func `parses reset time from end_time millisecond timestamp`() throws {
        // Given: end_time = 1735689600000 ms → 1735689600 seconds
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // Then
        let expectedDate = Date(timeIntervalSince1970: 1735689600.0)
        #expect(snapshot.quotas[0].resetsAt == expectedDate)
    }

    @Test
    func `handles multiple models`() throws {
        // Given
        let data = Data(Self.sampleMultiModelResponse.utf8)

        // When
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // Then
        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("minimax-m2"))
        #expect(snapshot.quotas[1].quotaType == .modelSpecific("minimax-m1"))

        // Second model: usage_count=400 is REMAINING out of 500 → 80% remaining
        let expectedPercent = Double(400) / Double(500) * 100.0
        #expect(snapshot.quotas[1].percentRemaining == expectedPercent)
    }

    @Test
    func `handles error response with non-zero status_code`() throws {
        // Given
        let data = Data(Self.sampleErrorResponse.utf8)

        // When & Then
        #expect(throws: ProbeError.self) {
            try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        }
    }

    @Test
    func `handles empty model_remains`() throws {
        // Given
        let data = Data(Self.sampleEmptyRemainsResponse.utf8)

        // When & Then
        #expect(throws: ProbeError.noData) {
            try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        }
    }

    @Test
    func `generates reset text with usage counts`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // Then
        // usage_count=255 is remaining, so used = 1500 - 255 = 1245
        #expect(snapshot.quotas[0].resetText == "1245/1500 requests")
    }

    @Test
    func `handles missing end_time gracefully`() throws {
        // Given
        let data = Data(Self.sampleNoEndTimeResponse.utf8)

        // When
        let snapshot = try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")

        // Then
        #expect(snapshot.quotas[0].resetsAt == nil)
        #expect(snapshot.quotas[0].percentRemaining == 50.0)
    }

    @Test
    func `throws parseFailed on invalid JSON`() throws {
        // Given
        let data = Data("not json".utf8)

        // When & Then
        #expect(throws: ProbeError.self) {
            try MiniMaxUsageProbe.parseResponse(data, providerId: "minimax")
        }
    }
}
