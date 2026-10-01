import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct DeepSeekUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleSuccessResponse = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "USD",
          "total_balance": "40.00",
          "granted_balance": "10.00",
          "topped_up_balance": "30.00"
        }
      ]
    }
    """

    static let sampleCNYResponse = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",
          "total_balance": "110.00",
          "granted_balance": "10.00",
          "topped_up_balance": "100.00"
        }
      ]
    }
    """

    static let sampleMultiCurrencyResponse = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",
          "total_balance": "110.00",
          "granted_balance": "10.00",
          "topped_up_balance": "100.00"
        },
        {
          "currency": "USD",
          "total_balance": "40.00",
          "granted_balance": "10.00",
          "topped_up_balance": "30.00"
        }
      ]
    }
    """

    static let sampleMissingFieldsResponse = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "USD",
          "total_balance": "40.00",
          "topped_up_balance": "30.00"
        }
      ]
    }
    """

    static let sampleEmptyBalanceInfosResponse = """
    {
      "is_available": true,
      "balance_infos": []
    }
    """

    static let sampleUnavailableResponse = """
    {
      "is_available": false,
      "balance_infos": [
        {
          "currency": "USD",
          "total_balance": "5.00",
          "granted_balance": "0.00",
          "topped_up_balance": "5.00"
        }
      ]
    }
    """

    // MARK: - Parsing Tests

    @Test
    func `parses balance_infos into a single balance quota`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].quotaType == .modelSpecific("Balance"))
        #expect(snapshot.providerId == "deepseek")
    }

    @Test
    func `maps total_balance string to dollarRemaining`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then: balance is unbounded, so percent is always 100
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(40))
        #expect(snapshot.quotas[0].percentRemaining == 100)
        #expect(snapshot.quotas[0].isDollarBased)
        // Currency is detected from the response, not hardcoded to USD
        #expect(snapshot.quotas[0].currency == "USD")
        #expect(snapshot.quotas[0].formattedDollarRemaining == "$40.00")
    }

    @Test
    func `uses first entry as primary currency when multiple present`() throws {
        // Given: CNY is the account's primary balance, listed first
        let data = Data(Self.sampleMultiCurrencyResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then: the primary (first) currency is used, not a later USD entry
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(110))
        #expect(snapshot.quotas[0].currency == "CNY")
        #expect(snapshot.quotas[0].formattedDollarRemaining == "¥110.00")
    }

    @Test
    func `falls back to first entry when no USD present`() throws {
        // Given
        let data = Data(Self.sampleCNYResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then: CNY balance is detected and displayed with the ¥ symbol
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(110))
        #expect(snapshot.quotas[0].currency == "CNY")
        #expect(snapshot.quotas[0].formattedDollarRemaining == "¥110.00")
    }

    @Test
    func `builds breakdown resetText`() throws {
        // Given
        let data = Data(Self.sampleSuccessResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then
        #expect(snapshot.quotas[0].resetText == "Paid: $30.00 · Granted: $10.00")
    }

    @Test
    func `builds CNY breakdown resetText`() throws {
        // Given
        let data = Data(Self.sampleCNYResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then
        #expect(snapshot.quotas[0].resetText == "Paid: ¥100.00 · Granted: ¥10.00")
    }

    @Test
    func `handles missing optional balance fields`() throws {
        // Given: granted_balance omitted
        let data = Data(Self.sampleMissingFieldsResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then: only the present part appears in the breakdown
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas[0].resetText == "Paid: $30.00")
    }

    @Test
    func `maps unavailable balance to depleted status`() throws {
        // Given: is_available false means the balance can't be used for API calls
        let data = Data(Self.sampleUnavailableResponse.utf8)

        // When
        let snapshot = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")

        // Then: quota is depleted but the balance amount is still surfaced
        #expect(snapshot.quotas[0].percentRemaining == 0)
        #expect(snapshot.quotas[0].status == .depleted)
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(5))
    }

    @Test
    func `throws noData on empty balance_infos`() throws {
        // Given
        let data = Data(Self.sampleEmptyBalanceInfosResponse.utf8)

        // When & Then
        #expect(throws: ProbeError.noData) {
            try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")
        }
    }

    @Test
    func `throws parseFailed on invalid JSON`() throws {
        // Given
        let data = Data("not json".utf8)

        // When & Then: must be parseFailed specifically, not any ProbeError
        do {
            _ = try DeepSeekUsageProbe.parseResponse(data, providerId: "deepseek")
            Issue.record("Expected ProbeError.parseFailed")
        } catch {
            guard case ProbeError.parseFailed = error else {
                Issue.record("Expected ProbeError.parseFailed, got \(error)")
                return
            }
        }
    }
}
