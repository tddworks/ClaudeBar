import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct VercelUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleCreditsResponse = """
    {
      "balance": 95.50,
      "total_used": 4.50
    }
    """

    static let sampleZeroBalanceResponse = """
    {
      "balance": 0.00,
      "total_used": 20.00
    }
    """

    static let sampleLargeBalanceResponse = """
    {
      "balance": 1245.67,
      "total_used": 312.33
    }
    """

    // MARK: - Parsing Tests

    @Test
    func `parses credits response into UsageSnapshot`() throws {
        // Given
        let data = Data(Self.sampleCreditsResponse.utf8)

        // When
        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.providerId == "vercel-gateway")
    }

    @Test
    func `maps balance to dollarRemaining`() throws {
        // Given
        let data = Data(Self.sampleCreditsResponse.utf8)

        // When
        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        // Then
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "95.50"))
    }

    @Test
    func `quota is dollar based`() throws {
        // Given
        let data = Data(Self.sampleCreditsResponse.utf8)

        // When
        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        // Then
        let quota = snapshot.quotas[0]
        #expect(quota.isDollarBased == true)
        #expect(quota.formattedDollarRemaining == "$95.50")
    }

    @Test
    func `uses 100 percent remaining for uncapped balance`() throws {
        // Given
        let data = Data(Self.sampleCreditsResponse.utf8)

        // When
        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        // Then
        #expect(snapshot.quotas[0].percentRemaining == 100)
    }

    @Test
    func `parses zero balance`() throws {
        // Given
        let data = Data(Self.sampleZeroBalanceResponse.utf8)

        // When
        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        // Then
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "0.00"))
        #expect(snapshot.quotas[0].formattedDollarRemaining == "$0.00")
    }

    @Test
    func `parses large balance`() throws {
        // Given
        let data = Data(Self.sampleLargeBalanceResponse.utf8)

        // When
        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        // Then
        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "1245.67"))
    }

    @Test
    func `accepts string encoded balance for compatible gateways`() throws {
        let data = Data("{\"balance\": \"95.50\", \"total_used\": \"4.50\"}".utf8)

        let snapshot = try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")

        #expect(snapshot.quotas[0].dollarRemaining == Decimal(string: "95.50"))
    }

    @Test
    func `throws parseFailed on invalid JSON`() throws {
        // Given
        let data = Data("not json".utf8)

        // When & Then
        #expect(throws: ProbeError.self) {
            try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")
        }
    }

    @Test
    func `throws parseFailed when balance missing`() throws {
        // Given
        let data = Data("{\"total_used\": 4.50}".utf8)

        // When & Then
        #expect(throws: ProbeError.self) {
            try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")
        }
    }

    @Test
    func `throws parseFailed on invalid balance format`() throws {
        // Given
        let data = Data("{\"balance\": \"abc\", \"total_used\": 4.50}".utf8)

        // When & Then
        #expect(throws: ProbeError.self) {
            try VercelUsageProbe.parseResponse(data, providerId: "vercel-gateway")
        }
    }
}
