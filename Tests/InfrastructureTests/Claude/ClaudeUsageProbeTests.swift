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

    // MARK: - Absolute Time Parsing Tests

    @Test
    func `parses reset date with time only and timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets 4:59pm (America/New_York)" — should resolve to a Date today or tomorrow
        let result = probe.parseResetDate("Resets 4:59pm (America/New_York)")
        #expect(result != nil, "Should parse time-only format with timezone")
        if let date = result {
            // Should be within the next 24 hours
            let diff = date.timeIntervalSinceNow
            #expect(diff > -60) // Allow small margin for test execution
            #expect(diff < 24 * 3600 + 60)
        }
    }

    @Test
    func `parses reset date with short time and timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets 3pm (Asia/Shanghai)" — short time without minutes
        let result = probe.parseResetDate("Resets 3pm (Asia/Shanghai)")
        #expect(result != nil, "Should parse short time format like 3pm")
    }

    @Test
    func `parses reset date with month day and time with timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets Dec 25 at 4:59am (Asia/Shanghai)"
        let result = probe.parseResetDate("Resets Dec 25 at 4:59am (Asia/Shanghai)")
        #expect(result != nil, "Should parse 'Mon DD at H:MMam (TZ)' format")
    }

    @Test
    func `parses reset date with month day comma time and timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets Jan 15, 3:30pm (America/Los_Angeles)"
        let result = probe.parseResetDate("Resets Jan 15, 3:30pm (America/Los_Angeles)")
        #expect(result != nil, "Should parse 'Mon DD, H:MMpm (TZ)' format")
    }

    @Test
    func `parses reset date with month day comma time without timezone`() {
        let probe = ClaudeUsageProbe()

        // "Resets Jan 15, 3:30pm"
        let result = probe.parseResetDate("Resets Jan 15, 3:30pm")
        #expect(result != nil, "Should parse 'Mon DD, H:MMpm' without timezone")
    }

    @Test
    func `parses reset date with month day year and timezone`() {
        let probe = ClaudeUsageProbe()

        // Always use a future year so the test never goes stale
        let futureYear = Calendar.current.component(.year, from: Date()) + 1
        let result = probe.parseResetDate("Resets Jan 1, \(futureYear) (America/New_York)")
        #expect(result != nil, "Should parse 'Mon DD, YYYY (TZ)' format")
    }

    @Test
    func `parses reset date with month day only`() {
        let probe = ClaudeUsageProbe()

        // "Resets Dec 28"
        let result = probe.parseResetDate("Resets Dec 28")
        #expect(result != nil, "Should parse 'Mon DD' date-only format")
    }

    @Test
    func `parsed absolute date has correct timezone`() {
        let probe = ClaudeUsageProbe()

        // Two calls with different timezones for the same time should yield different Dates
        let eastern = probe.parseResetDate("Resets 4:59pm (America/New_York)")
        let shanghai = probe.parseResetDate("Resets 4:59pm (Asia/Shanghai)")
        #expect(eastern != nil)
        #expect(shanghai != nil)
        if let e = eastern, let s = shanghai {
            // These should NOT be equal — different timezones for the same wall-clock time
            #expect(e != s, "Same wall-clock time in different timezones should produce different Dates")
        }
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
            autoResponses: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountTier == .claudeMax)
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
            autoResponses: .any
        ).willReturn(CLIResult(output: usageOutput, exitCode: 0))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)

        // When
        let snapshot = try await probe.probe()

        // Then
        #expect(snapshot.accountTier == .claudePro)
        #expect(snapshot.costUsage != nil)
        #expect(snapshot.costUsage?.totalCost == Decimal(string: "5.41"))
        #expect(snapshot.costUsage?.budget == Decimal(string: "20.00"))
        #expect(snapshot.costUsage?.kind == .extraUsage)
        #expect(snapshot.quotas.count >= 1)
    }

    // MARK: - Account Info from ClaudeAccountInfoResolver

    @Test
    func `probe resolves account info from config file`() async throws {
        // Given - new tabbed CLI output (no account info in /usage tab)
        let mockExecutor = MockCLIExecutor()

        let tabbedUsageOutput = """
          Status   Config   Usage

        Current session
        ▌                                                  1% used
        Resets 12am (Asia/Shanghai)

        Current week (all models)
        ██████████████████████▌                            45% used
        Resets 10:59am (Asia/Shanghai)

        Extra usage
        Extra usage not enabled • /extra-usage to enable

        Esc to cancel
        """

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/usage" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: tabbedUsageOutput, exitCode: 0))

        // Mock resolver returns account info
        let mockResolver = MockAccountInfoResolving()
        given(mockResolver).resolve().willReturn(AccountInfo(email: "user@example.com", organization: "testuser"))

        let probe = ClaudeUsageProbe(cliExecutor: mockExecutor, accountInfoResolver: mockResolver)

        // When
        let snapshot = try await probe.probe()

        // Then - account info from config, tier from CLI output
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "testuser")
        #expect(snapshot.quotas.count >= 1)
        #expect(snapshot.sessionQuota?.percentRemaining == 99)
    }

    // MARK: - Setup Token Environment Exclusion Tests

    @Test
    func `envExclusions includes CLAUDE_CODE_OAUTH_TOKEN`() {
        // The CLI probe must strip the setup-token env var so that
        // `claude /usage` falls back to stored credentials with full scope.
        #expect(ClaudeUsageProbe.envExclusions.contains("CLAUDE_CODE_OAUTH_TOKEN"))
    }

    @Test
    func `default init creates executor that excludes setup token env var`() {
        // When ClaudeUsageProbe is created without an explicit CLIExecutor,
        // the default executor should be configured to exclude CLAUDE_CODE_OAUTH_TOKEN.
        // We verify this indirectly by checking the static envExclusions constant.
        let exclusions = ClaudeUsageProbe.envExclusions
        #expect(exclusions == ["CLAUDE_CODE_OAUTH_TOKEN"])
    }
}
