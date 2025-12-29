import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct GeminiCLIProbeParsingTests {

    // MARK: - Sample Data

    static let sampleStatsOutput = """
    ╭─────────────────────────────────────────────────────────────────╮
    │                        Gemini Stats                              │
    ├─────────────────────────────────────────────────────────────────┤
    │ Model               │ Used    │ Remaining                       │
    ├─────────────────────────────────────────────────────────────────┤
    │ gemini-2.5-pro      │   -     │ 100.0% (Resets in 24h)          │
    │ gemini-2.5-flash    │   5     │  95.0% (Resets in 12h)          │
    │ gemini-2.0-flash    │  10     │  80.5% (Resets in 6h)           │
    ╰─────────────────────────────────────────────────────────────────╯
    """

    static let sampleOutputWithANSICodes = """
    \u{1B}[32m╭─────────────────────────────────────────────────────────────────╮\u{1B}[0m
    \u{1B}[32m│\u{1B}[0m                        Gemini Stats                              \u{1B}[32m│\u{1B}[0m
    │ gemini-2.5-pro      │   -     │ 75.0% (Resets in 24h)           │
    \u{1B}[32m╰─────────────────────────────────────────────────────────────────╯\u{1B}[0m
    """

    static let loginRequiredOutput = """
    Welcome to Gemini CLI!

    Please login with Google to continue.
    Run: gemini auth login
    """

    static let apiKeyOutput = """
    You can use Gemini API key for authentication.
    """

    static let waitingForAuthOutput = """
    Waiting for auth to complete...
    Please open the browser and complete authentication.
    """

    // MARK: - Parsing Success Tests

    @Test
    func `parses model quota from stats output`() throws {
        // When
        let snapshot = try GeminiCLIProbe.parse(Self.sampleStatsOutput)

        // Then
        #expect(snapshot.providerId == "gemini")
        #expect(snapshot.quotas.count == 3)
    }

    @Test
    func `extracts correct percentage remaining for each model`() throws {
        // When
        let snapshot = try GeminiCLIProbe.parse(Self.sampleStatsOutput)

        // Then
        let quotasByModel = Dictionary(uniqueKeysWithValues: snapshot.quotas.map { ($0.quotaType, $0.percentRemaining) })

        #expect(quotasByModel[.modelSpecific("gemini-2.5-pro")] == 100.0)
        #expect(quotasByModel[.modelSpecific("gemini-2.5-flash")] == 95.0)
        #expect(quotasByModel[.modelSpecific("gemini-2.0-flash")] == 80.5)
    }

    @Test
    func `extracts reset text for each model`() throws {
        // When
        let snapshot = try GeminiCLIProbe.parse(Self.sampleStatsOutput)

        // Then
        let proModel = snapshot.quotas.first { $0.quotaType == .modelSpecific("gemini-2.5-pro") }
        #expect(proModel?.resetText == "Resets in 24h")

        let flashModel = snapshot.quotas.first { $0.quotaType == .modelSpecific("gemini-2.5-flash") }
        #expect(flashModel?.resetText == "Resets in 12h")
    }

    @Test
    func `strips ANSI codes before parsing`() throws {
        // When
        let snapshot = try GeminiCLIProbe.parse(Self.sampleOutputWithANSICodes)

        // Then
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 75.0)
    }

    @Test
    func `sets provider ID to gemini`() throws {
        // When
        let snapshot = try GeminiCLIProbe.parse(Self.sampleStatsOutput)

        // Then
        #expect(snapshot.providerId == "gemini")
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "gemini" })
    }

    @Test
    func `sets captured timestamp`() throws {
        // Given
        let beforeParse = Date()

        // When
        let snapshot = try GeminiCLIProbe.parse(Self.sampleStatsOutput)

        // Then
        let afterParse = Date()
        #expect(snapshot.capturedAt >= beforeParse)
        #expect(snapshot.capturedAt <= afterParse)
    }

    // MARK: - Authentication Error Tests

    @Test
    func `throws authenticationRequired when login prompt detected`() {
        // When/Then
        #expect(throws: ProbeError.authenticationRequired) {
            try GeminiCLIProbe.parse(Self.loginRequiredOutput)
        }
    }

    @Test
    func `throws authenticationRequired when API key prompt detected`() {
        // When/Then
        #expect(throws: ProbeError.authenticationRequired) {
            try GeminiCLIProbe.parse(Self.apiKeyOutput)
        }
    }

    @Test
    func `throws authenticationRequired when waiting for auth detected`() {
        // When/Then
        #expect(throws: ProbeError.authenticationRequired) {
            try GeminiCLIProbe.parse(Self.waitingForAuthOutput)
        }
    }

    // MARK: - Parse Error Tests

    @Test
    func `throws parseFailed when no usage data found`() {
        // Given
        let emptyOutput = "Some random text with no usage data"

        // When/Then
        #expect(throws: ProbeError.self) {
            try GeminiCLIProbe.parse(emptyOutput)
        }
    }

    @Test
    func `throws parseFailed for completely empty output`() {
        // When/Then
        #expect(throws: ProbeError.self) {
            try GeminiCLIProbe.parse("")
        }
    }

    // MARK: - Edge Cases

    @Test
    func `handles decimal percentages correctly`() throws {
        // Given
        let outputWithDecimals = """
        │ gemini-2.5-pro      │   -     │ 99.99% (Resets in 24h)          │
        """

        // When
        let snapshot = try GeminiCLIProbe.parse(outputWithDecimals)

        // Then
        #expect(snapshot.quotas.first?.percentRemaining == 99.99)
    }

    @Test
    func `handles zero percentage`() throws {
        // Given
        let zeroOutput = """
        │ gemini-2.5-pro      │   -     │ 0.0% (Resets in 1h)             │
        """

        // When
        let snapshot = try GeminiCLIProbe.parse(zeroOutput)

        // Then
        #expect(snapshot.quotas.first?.percentRemaining == 0.0)
        #expect(snapshot.quotas.first?.status == .depleted)
    }

    @Test
    func `handles model names with version numbers`() throws {
        // Given
        let outputWithVersions = """
        │ gemini-2.5-pro-002  │   -     │ 50.0% (Resets in 24h)           │
        │ gemini-1.5-flash-8b │   -     │ 75.0% (Resets in 12h)           │
        """

        // When
        let snapshot = try GeminiCLIProbe.parse(outputWithVersions)

        // Then
        #expect(snapshot.quotas.count == 2)
        let modelNames = snapshot.quotas.compactMap { quota -> String? in
            if case .modelSpecific(let name) = quota.quotaType { return name }
            return nil
        }
        #expect(modelNames.contains("gemini-2.5-pro-002"))
        #expect(modelNames.contains("gemini-1.5-flash-8b"))
    }
}
