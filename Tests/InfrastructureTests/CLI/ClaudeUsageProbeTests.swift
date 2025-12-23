import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct ClaudeUsageProbeTests {

    @Test
    func `isAvailable returns true when CLI executor finds binary`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when CLI executor cannot find binary`() async {
        // Given
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)
        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When & Then
        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Date Parsing Tests

    @Test
    func `parses reset date with days hours and minutes`() {
        let probe = ClaudeUsageProbe()
        let now = Date()
        
        // Days
        let d2 = probe.parseResetDate("resets in 2d")
        #expect(d2 != nil)
        #expect(d2!.timeIntervalSince(now) > 2 * 23 * 3600) // approx 2 days
        
        // Hours and minutes
        let hm = probe.parseResetDate("resets in 2h 15m")
        #expect(hm != nil)
        let diff = hm!.timeIntervalSince(now)
        #expect(diff > 2 * 3600 + 14 * 60)
        #expect(diff < 2 * 3600 + 16 * 60)
        
        // Just minutes
        let m30 = probe.parseResetDate("30m")
        #expect(m30 != nil)
        #expect(m30!.timeIntervalSince(now) > 29 * 60)
    }

    @Test
    func `parseResetDate returns nil for invalid input`() {
        let probe = ClaudeUsageProbe()
        #expect(probe.parseResetDate(nil) == nil)
        #expect(probe.parseResetDate("") == nil)
        #expect(probe.parseResetDate("no time here") == nil)
    }

    // MARK: - Helper Tests

    @Test
    func `cleanResetText adds resets prefix if missing`() {
        let probe = ClaudeUsageProbe()
        #expect(probe.cleanResetText("in 2h") == "Resets in 2h")
        #expect(probe.cleanResetText("Resets in 2h") == "Resets in 2h")
        #expect(probe.cleanResetText(nil) == nil)
    }

    @Test
    func `extractEmail finds email in various formats`() {
        let probe = ClaudeUsageProbe()
        // Old format
        #expect(probe.extractEmail(text: "Account: user@example.com") == "user@example.com")
        #expect(probe.extractEmail(text: "Email: user@example.com") == "user@example.com")
        // Header format
        #expect(probe.extractEmail(text: "Opus 4.5 · Claude Max · user@example.com's Organization") == "user@example.com")
        #expect(probe.extractEmail(text: "Opus 4.5 · Claude Pro · test@test.com's Org") == "test@test.com")
        // No email
        #expect(probe.extractEmail(text: "No email here") == nil)
        #expect(probe.extractEmail(text: "Opus 4.5 · Claude Pro · Organization") == nil)
    }

    @Test
    func `extractOrganization finds org`() {
        let probe = ClaudeUsageProbe()
        // Old format
        #expect(probe.extractOrganization(text: "Organization: Acme Corp") == "Acme Corp")
        #expect(probe.extractOrganization(text: "Org: Acme Corp") == "Acme Corp")
        // Header format with email
        #expect(probe.extractOrganization(text: "Opus 4.5 · Claude Max · user@example.com's Organization") == "user@example.com's Organization")
        // Header format without email - just company name
        #expect(probe.extractOrganization(text: "Opus 4.5 · Claude Pro · My Company") == "My Company")
        // Header format with just a person's name
        #expect(probe.extractOrganization(text: "Opus 4.5 · Claude Pro · Vincent Young") == "Vincent Young")
    }

    @Test
    func `extractLoginMethod finds method`() {
        let probe = ClaudeUsageProbe()
        #expect(probe.extractLoginMethod(text: "Login method: Claude Max") == "Claude Max")
    }

    @Test
    func `extractFolderFromTrustPrompt finds path`() {
        let probe = ClaudeUsageProbe()
        let output = "Do you trust the files in this folder?\n/Users/test/project\n\nYes/No"
        #expect(probe.extractFolderFromTrustPrompt(output) == "/Users/test/project")
    }

    @Test
    func `probeWorkingDirectory creates and returns URL`() {
        let probe = ClaudeUsageProbe()
        let url = probe.probeWorkingDirectory()
        #expect(url.path.contains("ClaudeBar/Probe"))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Probe Tests

    @Test
    func `probe extracts account type from usage output`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()

        // /usage returns Max account with quota data
        let usageOutput = """
        Opus 4.5 · Claude Max · user@example.com's Organization

        Current session
        ████████████████░░░░ 65% left
        Resets in 2h 15m

        Current week (all models)
        ██████████░░░░░░░░░░ 35% left
        Resets Dec 28
        """

        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            sendOnSubstrings: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountType == .max)
        #expect(snapshot.quotas.count >= 1)
    }

    @Test
    func `probe extracts Pro account with Extra usage`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()

        let usageOutput = """
        Opus 4.5 · Claude Pro · user@example.com's Organization

        Current session
        █████░░░░░░░░░░░░░░░ 1% used
        Resets 4:59pm (America/New_York)

        Current week (all models)
        █████████████████░░░ 36% used
        Resets Dec 25 at 2:59pm (America/New_York)

        Extra usage
        █████░░░░░░░░░░░░░░░ 27% used
        $5.41 / $20.00 spent · Resets Jan 1, 2026 (America/New_York)
        """

        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            sendOnSubstrings: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountType == .pro)
        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20.00"))
        #expect(snapshot.quotas.count >= 1)
    }
}
