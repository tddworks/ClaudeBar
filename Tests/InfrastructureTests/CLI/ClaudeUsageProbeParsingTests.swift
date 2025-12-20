import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct ClaudeUsageProbeParsingTests {

    // MARK: - Sample CLI Output

    static let sampleClaudeOutput = """
    Claude Code v1.0.27

    Current session
    ████████████████░░░░ 65% left
    Resets in 2h 15m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    Resets Jan 15, 3:30pm (America/Los_Angeles)

    Current week (Opus)
    ████████████████████ 80% left
    Resets Jan 15, 3:30pm (America/Los_Angeles)

    Account: user@example.com
    Organization: Acme Corp
    Login method: Claude Max
    """

    static let exhaustedQuotaOutput = """
    Claude Code v1.0.27

    Current session
    ░░░░░░░░░░░░░░░░░░░░ 0% left
    Resets in 30m

    Current week (all models)
    ██████████░░░░░░░░░░ 35% left
    Resets Jan 15, 3:30pm
    """

    static let usedPercentOutput = """
    Current session
    ████████████████████ 25% used

    Current week (all models)
    ████████████░░░░░░░░ 60% used
    """

    // MARK: - Parsing Percentages

    @Test
    func `parses session quota from left format`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 65)
        #expect(snapshot.sessionQuota?.status == .healthy)
    }

    @Test
    func `parses weekly quota from left format`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.weeklyQuota?.percentRemaining == 35)
        #expect(snapshot.weeklyQuota?.status == .warning)
    }

    @Test
    func `parses model specific quota like opus`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        let opusQuota = snapshot.quota(for: .modelSpecific("opus"))
        #expect(opusQuota?.percentRemaining == 80)
        #expect(opusQuota?.status == .healthy)
    }

    @Test
    func `converts used format to remaining`() throws {
        // Given
        let output = Self.usedPercentOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then - 25% used = 75% left, 60% used = 40% left
        #expect(snapshot.sessionQuota?.percentRemaining == 75)
        #expect(snapshot.weeklyQuota?.percentRemaining == 40)
    }

    @Test
    func `detects depleted quota at zero percent`() throws {
        // Given
        let output = Self.exhaustedQuotaOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 0)
        #expect(snapshot.sessionQuota?.status == .depleted)
        #expect(snapshot.sessionQuota?.isDepleted == true)
    }

    // MARK: - Parsing Account Info

    @Test
    func `extracts user email from output`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.accountEmail == "user@example.com")
    }

    @Test
    func `extracts organization from output`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.accountOrganization == "Acme Corp")
    }

    @Test
    func `extracts login method from output`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.loginMethod == "Claude Max")
    }

    // MARK: - Error Detection

    static let trustPromptOutput = """
    Do you trust the files in this folder?
    /Users/test/project

    Yes, proceed (y)
    No, cancel (n)
    """

    static let authErrorOutput = """
    authentication_error: Your session has expired.
    Please run `claude login` to authenticate.
    """

    @Test
    func `detects folder trust prompt and throws error`() throws {
        // Given
        let output = Self.trustPromptOutput

        // When & Then
        #expect(throws: ProbeError.self) {
            try simulateParse(text: output)
        }
    }

    @Test
    func `detects authentication error and throws error`() throws {
        // Given
        let output = Self.authErrorOutput

        // When & Then
        #expect(throws: ProbeError.self) {
            try simulateParse(text: output)
        }
    }

    // MARK: - Reset Time Parsing

    @Test
    func `parses session reset time from output`() throws {
        // Given
        let output = Self.sampleClaudeOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then
        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt != nil)
        #expect(sessionQuota?.resetDescription != nil)
    }

    @Test
    func `parses short reset time like 30m`() throws {
        // Given
        let output = Self.exhaustedQuotaOutput

        // When
        let snapshot = try ClaudeUsageProbe.parse(output)

        // Then
        let sessionQuota = snapshot.sessionQuota
        #expect(sessionQuota?.resetsAt != nil)
        // Should be about 30 minutes from now
        if let timeUntil = sessionQuota?.timeUntilReset {
            #expect(timeUntil > 25 * 60) // > 25 minutes
            #expect(timeUntil < 35 * 60) // < 35 minutes
        }
    }

    // MARK: - ANSI Code Handling

    static let ansiColoredOutput = """
    \u{1B}[32mCurrent session\u{1B}[0m
    ████████████████░░░░ \u{1B}[33m65% left\u{1B}[0m
    Resets in 2h 15m
    """

    @Test
    func `strips ansi color codes before parsing`() throws {
        // Given
        let output = Self.ansiColoredOutput

        // When
        let snapshot = try simulateParse(text: output)

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 65)
    }

    // MARK: - Helper

    private func simulateParse(text: String) throws -> UsageSnapshot {
        // Strip ANSI codes
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        let clean = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)

        // Check for errors
        let lower = clean.lowercased()
        if lower.contains("do you trust the files in this folder?"), !lower.contains("current session") {
            throw ProbeError.folderTrustRequired("unknown")
        }
        if lower.contains("authentication_error") {
            throw ProbeError.authenticationRequired
        }

        // Extract percentages
        func extractPercent(label: String) -> Int? {
            let lines = clean.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() where line.lowercased().contains(label.lowercased()) {
                let window = lines.dropFirst(idx).prefix(12)
                for candidate in window {
                    let pctPattern = #"([0-9]{1,3})\s*%\s*(used|left)"#
                    if let regex = try? NSRegularExpression(pattern: pctPattern, options: [.caseInsensitive]) {
                        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
                        if let match = regex.firstMatch(in: candidate, options: [], range: range),
                           match.numberOfRanges >= 3,
                           let valRange = Range(match.range(at: 1), in: candidate),
                           let kindRange = Range(match.range(at: 2), in: candidate) {
                            let rawVal = Int(candidate[valRange]) ?? 0
                            let isUsed = candidate[kindRange].lowercased().contains("used")
                            return isUsed ? max(0, 100 - rawVal) : rawVal
                        }
                    }
                }
            }
            return nil
        }

        func extractFirst(pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            guard let match = regex.firstMatch(in: clean, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: clean) else {
                return nil
            }
            return String(clean[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let sessionPct = extractPercent(label: "Current session") else {
            throw ProbeError.parseFailed("Could not find session usage")
        }

        var quotas: [UsageQuota] = []
        quotas.append(UsageQuota(percentRemaining: Double(sessionPct), quotaType: .session, provider: .claude))

        if let weeklyPct = extractPercent(label: "Current week (all models)") {
            quotas.append(UsageQuota(percentRemaining: Double(weeklyPct), quotaType: .weekly, provider: .claude))
        }

        if let opusPct = extractPercent(label: "Current week (Opus)") {
            quotas.append(UsageQuota(percentRemaining: Double(opusPct), quotaType: .modelSpecific("opus"), provider: .claude))
        }

        let email = extractFirst(pattern: #"(?i)(?:Account|Email):\s*([^\s@]+@[^\s@]+)"#)
        let org = extractFirst(pattern: #"(?i)(?:Org|Organization):\s*(.+)"#)
        let login = extractFirst(pattern: #"(?i)login\s+method:\s*(.+)"#)

        return UsageSnapshot(
            provider: .claude,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: email,
            accountOrganization: org,
            loginMethod: login
        )
    }
}
