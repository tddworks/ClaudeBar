import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct AmpCodeUsageProbeParsingTests {

    // MARK: - Sample Data

    static let sampleOutput = """
    Signed in as user@example.com (username)
    Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
    Individual credits: $0 remaining - https://ampcode.com/settings
    """


    static let sampleOutputZeroRemaining = """
    Signed in as user@example.com (username)
    Amp Free: $0/$20 remaining (replenishes +$0.83/hour) - https://ampcode.com/settings#amp-free
    Individual credits: $0 remaining - https://ampcode.com/settings
    """

    static let sampleOutputWithIndividualCredits = """
    Signed in as user@example.com (username)
    Amp Free: $17.59/$20 remaining (replenishes +$0.83/hour) [+100% bonus for 19 more days] - https://ampcode.com/settings#amp-free
    Individual credits: $50 remaining - https://ampcode.com/settings
    """

    static let sampleOutputIndividualCreditsOnly = """
    Signed in as user@example.com (username)
    Individual credits: $50 remaining - https://ampcode.com/settings
    """

    // MARK: - Parsing Tests

    @Test
    func `parses free tier credits into percentage`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - $17.59/$20 = 87.95%
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota != nil)
        #expect(freeQuota!.percentRemaining == 87.95)
    }

    @Test
    func `extracts account email`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `handles zero remaining with total`() throws {
        // Given
        let text = Self.sampleOutputZeroRemaining

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - $0/$20 = 0%
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota != nil)
        #expect(freeQuota!.percentRemaining == 0.0)
    }

    @Test
    func `parses both free and individual credits as separate quotas`() throws {
        // Given - both lines present with non-zero values
        let text = Self.sampleOutputWithIndividualCredits

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - both quotas parsed
        #expect(snapshot.quotas.count == 2)
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(freeQuota != nil)
        #expect(creditsQuota != nil)
    }

    @Test
    func `individual credits has dollarRemaining set`() throws {
        // Given
        let text = Self.sampleOutputWithIndividualCredits

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - $50 remaining with no cap
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(creditsQuota?.dollarRemaining == 50)
        #expect(creditsQuota?.percentRemaining == 100)
    }

    @Test
    func `individual credits zero remaining has dollarRemaining zero`() throws {
        // Given - "$0 remaining" with no denominator
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(creditsQuota?.dollarRemaining == 0)
        #expect(creditsQuota?.percentRemaining == 100)
    }

    @Test
    func `free tier quota has dollar breakdown in resetText`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - shows $remaining/$total like Copilot shows x/y requests
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota?.resetText == "$17.59/$20.00")
    }

    @Test
    func `zero remaining quota has dollar breakdown in resetText`() throws {
        // Given
        let text = Self.sampleOutputZeroRemaining

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota?.resetText == "$0.00/$20.00")
    }

    @Test
    func `individual credits has no resetText`() throws {
        // Given - balance-only line has no total, so no breakdown
        let text = Self.sampleOutputWithIndividualCredits

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        let creditsQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(creditsQuota?.resetText == nil)
    }

    @Test
    func `free tier quota has nil dollarRemaining`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then - percentage-based quota should not have dollarRemaining
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        #expect(freeQuota?.dollarRemaining == nil)
    }

    @Test
    func `individual credits only is valid snapshot`() throws {
        // Given - no free tier line, only individual credits
        let text = Self.sampleOutputIndividualCreditsOnly

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.quotas.count == 1)
        let individualQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Individual") }
        #expect(individualQuota != nil)
        #expect(individualQuota?.dollarRemaining == 50)
    }

    @Test
    func `maps to correct QuotaType`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        let freeQuota = snapshot.quotas.first { $0.quotaType == .modelSpecific("Free") }
        if let freeQuota, case .modelSpecific(let name) = freeQuota.quotaType {
            #expect(name == "Free")
        } else {
            Issue.record("Expected modelSpecific quota type")
        }
    }

    @Test
    func `sets providerId correctly`() throws {
        // Given
        let text = Self.sampleOutput

        // When
        let snapshot = try AmpCodeUsageProbe.parse(text)

        // Then
        #expect(snapshot.providerId == "ampcode")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "ampcode" })
    }

    // MARK: - Error Handling Tests

    @Test
    func `throws parseFailed on empty output`() throws {
        // Given
        let text = ""

        // When/Then
        #expect(throws: ProbeError.self) {
            try AmpCodeUsageProbe.parse(text)
        }
    }

    @Test
    func `throws parseFailed on garbage output`() throws {
        // Given
        let text = "some random text that is not amp usage output"

        // When/Then
        #expect(throws: ProbeError.self) {
            try AmpCodeUsageProbe.parse(text)
        }
    }
}
