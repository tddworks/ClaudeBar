import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Mock clipboard reader for testing
final class MockClipboardReader: ClipboardReader, @unchecked Sendable {
    var content: String?

    init(content: String? = nil) {
        self.content = content
    }

    func readString() -> String? {
        content
    }
}

@Suite
struct ClaudeGuestPassSourceTests {

    // MARK: - Parsing Tests (for legacy format with URL in output)

    @Test
    func `parses guest passes with 3 remaining`() throws {
        // Given
        let output = """
        Guest passes · 3 left

          ┌──────────┐ ┌──────────┐ ┌──────────┐
           ) CC ✻ ┊ (   ) CC ✻ ┊ (   ) CC ✻ ┊ (
          └──────────┘ └──────────┘ └──────────┘

          https://claude.ai/referral/DJ_kWX90Xw

          Share a free week of Claude Code with friends.
        """

        // When
        let pass = try ClaudeGuestPassSource.parse(output)

        // Then
        #expect(pass.passesRemaining == 3)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/DJ_kWX90Xw")
    }

    @Test
    func `parses guest passes with 1 remaining`() throws {
        let output = """
        Guest passes · 1 left

          ┌──────────┐
           ) CC ✻ ┊ (
          └──────────┘

          https://claude.ai/referral/ABC123

          Share a free week of Claude Code with friends.
        """

        let pass = try ClaudeGuestPassSource.parse(output)

        #expect(pass.passesRemaining == 1)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/ABC123")
    }

    @Test
    func `parses guest passes with 0 remaining`() throws {
        let output = """
        Guest passes · 0 left

          https://claude.ai/referral/XYZ789

          Share a free week of Claude Code with friends.
        """

        let pass = try ClaudeGuestPassSource.parse(output)

        #expect(pass.passesRemaining == 0)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/XYZ789")
    }

    @Test
    func `parses URL without pass count`() throws {
        // Format where count is not shown but URL is
        let output = """
        https://claude.ai/referral/ABC123

        Share a free week of Claude Code with friends.
        """

        let pass = try ClaudeGuestPassSource.parse(output)

        #expect(pass.passesRemaining == nil)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/ABC123")
    }

    @Test
    func `throws error when no referral URL found`() {
        let output = """
        Guest passes · 3 left

          Share a free week of Claude Code with friends.
        """

        #expect(throws: UsageError.self) {
            _ = try ClaudeGuestPassSource.parse(output)
        }
    }

    @Test
    func `strips ANSI codes before parsing`() throws {
        // Output with ANSI color codes
        let output = "\u{001B}[1mGuest passes\u{001B}[0m · \u{001B}[32m3 left\u{001B}[0m\n\nhttps://claude.ai/referral/ABC123"

        let pass = try ClaudeGuestPassSource.parse(output)

        #expect(pass.passesRemaining == 3)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/ABC123")
    }

    // MARK: - Probe Behavior Tests (with URL in output)

    @Test
    func `probe returns GuestPass with URL from output`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let passOutput = """
        Guest passes · 2 left

          https://claude.ai/referral/TEST123

          Share a free week of Claude Code with friends.
        """

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/passes" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: passOutput, exitCode: 0))

        let probe = ClaudeGuestPassSource(cliExecutor: mockExecutor)

        // When
        let pass = try await probe.fetch()

        // Then
        #expect(pass.passesRemaining == 2)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/TEST123")
    }

    // MARK: - Probe Behavior Tests (clipboard mode - current behavior)

    @Test
    func `probe reads URL from clipboard when not in output`() async throws {
        // Given
        let mockExecutor = MockCLIExecutor()
        let mockClipboard = MockClipboardReader(content: "https://claude.ai/referral/CLIPBOARD123")

        // Output says copied but doesn't show URL
        let passOutput = """
        > /passes
          ⎿  Referral link copied to clipboard!
        """

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/passes" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: passOutput, exitCode: 0))

        let probe = ClaudeGuestPassSource(cliExecutor: mockExecutor, clipboardReader: mockClipboard)

        // When
        let pass = try await probe.fetch()

        // Then
        #expect(pass.passesRemaining == nil)  // Count not available in this format
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/CLIPBOARD123")
    }

    @Test
    func `probe throws when URL not in output or clipboard`() async {
        let mockExecutor = MockCLIExecutor()
        let mockClipboard = MockClipboardReader(content: "Some other clipboard content")

        let passOutput = """
        > /passes
          ⎿  Referral link copied to clipboard!
        """

        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        given(mockExecutor).execute(
            binary: .any,
            args: .matching { $0.first == "/passes" },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: passOutput, exitCode: 0))

        let probe = ClaudeGuestPassSource(cliExecutor: mockExecutor, clipboardReader: mockClipboard)

        await #expect(throws: UsageError.self) {
            _ = try await probe.fetch()
        }
    }

    @Test
    func `isAvailable returns true when binary exists`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")

        let probe = ClaudeGuestPassSource(cliExecutor: mockExecutor)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when binary not found`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)

        let probe = ClaudeGuestPassSource(cliExecutor: mockExecutor)

        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `probe throws on CLI execution failure`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willThrow(UsageError.executionFailed("CLI error"))

        let probe = ClaudeGuestPassSource(cliExecutor: mockExecutor)

        await #expect(throws: UsageError.self) {
            _ = try await probe.fetch()
        }
    }

    @Test
    func `guest passes run the claude cli at its chosen location`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.value("/opt/tools/bin/claude-work")).willReturn("/opt/tools/bin/claude-work")
        given(mockExecutor).locate(.value("claude")).willReturn(nil)
        let probe = ClaudeGuestPassSource(claudeBinary: { "/opt/tools/bin/claude-work" }, cliExecutor: mockExecutor)

        #expect(await probe.isAvailable())
    }
}
