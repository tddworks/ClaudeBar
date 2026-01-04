import Foundation
import Domain
import AppKit

/// Protocol for reading from the system clipboard (for testability)
public protocol ClipboardReader: Sendable {
    func readString() -> String?
}

/// Default clipboard reader using NSPasteboard
public final class SystemClipboardReader: ClipboardReader, @unchecked Sendable {
    public init() {}

    public func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

/// Probes the Claude CLI to fetch guest pass information.
/// Executes `claude /passes` which copies the referral link to clipboard.
public final class ClaudePassProbe: ClaudePassProbing, @unchecked Sendable {
    private let claudeBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor
    private let clipboardReader: ClipboardReader

    public init(
        claudeBinary: String = "claude",
        timeout: TimeInterval = 20.0,
        cliExecutor: CLIExecutor? = nil,
        clipboardReader: ClipboardReader? = nil
    ) {
        self.claudeBinary = claudeBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? DefaultCLIExecutor()
        self.clipboardReader = clipboardReader ?? SystemClipboardReader()
    }

    /// Checks if the Claude CLI is available
    public func isAvailable() async -> Bool {
        if cliExecutor.locate(claudeBinary) != nil {
            return true
        }

        // Log diagnostic info when binary not found
        let env = ProcessInfo.processInfo.environment
        AppLog.probes.error("Claude binary '\(claudeBinary)' not found in PATH")
        AppLog.probes.info("Current directory: \(FileManager.default.currentDirectoryPath)")
        AppLog.probes.info("PATH: \(env["PATH"] ?? "<not set>")")
        if let configDir = env["CLAUDE_CONFIG_DIR"] {
            AppLog.probes.info("CLAUDE_CONFIG_DIR: \(configDir)")
        }
        return false
    }

    /// Probes the CLI for guest pass information.
    /// The /passes command copies the referral URL to clipboard.
    public func probe() async throws -> ClaudePass {
        let workingDir = probeWorkingDirectory()
        AppLog.probes.info("Starting Claude probe with /passes command...")

        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: claudeBinary,
                args: ["/passes", "--allowed-tools", ""],
                input: "",
                timeout: timeout,
                workingDirectory: workingDir,
                autoResponses: [
                    "Esc to cancel": "\r",
                    "Ready to code here?": "\r",
                    "Press Enter to continue": "\r",
                    "ctrl+t to disable": "\r",
                ]
            )
        } catch {
            AppLog.probes.error("Claude /passes probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        let clean = Self.stripANSICodes(result.output)
        AppLog.probes.debug("Claude /passes output (cleaned): \(clean)")

        // Check if the command succeeded
        guard clean.lowercased().contains("copied to clipboard") ||
              clean.lowercased().contains("referral") else {
            AppLog.probes.error("Claude /passes failed: unexpected output")
            throw ProbeError.parseFailed("Command did not indicate success")
        }

        // Try to get URL from output first, then fall back to clipboard
        var referralURL: URL?

        // Try parsing from output (in case format changes to show URL)
        referralURL = Self.extractReferralURL(clean)

        // Fall back to reading from clipboard
        if referralURL == nil {
            if let clipboardContent = clipboardReader.readString(),
               let url = Self.extractReferralURL(clipboardContent) {
                referralURL = url
                AppLog.probes.info("Got referral URL from clipboard")
            }
        }

        guard let url = referralURL else {
            AppLog.probes.error("Claude /passes failed: could not find referral URL")
            throw ProbeError.parseFailed("Could not find referral URL")
        }

        // Try to extract pass count if available (may not be shown)
        let passCount = Self.extractPassesCount(clean)

        let pass = ClaudePass(passesRemaining: passCount, referralURL: url)
        if let count = passCount {
            AppLog.probes.info("Claude passes probe success: \(count) passes remaining")
        } else {
            AppLog.probes.info("Claude passes probe success: referral URL obtained")
        }

        return pass
    }

    // MARK: - Parsing

    /// Parses Claude CLI /passes output into a ClaudePass (for testing)
    /// This handles both the old format (with visible URL) and new format (clipboard only)
    public static func parse(_ text: String) throws -> ClaudePass {
        let clean = stripANSICodes(text)

        // Try to extract referral URL from the text
        guard let referralURL = extractReferralURL(clean) else {
            // If no URL in output, it might be clipboard-only mode
            AppLog.probes.debug("No referral URL in output, may need clipboard")
            throw ProbeError.parseFailed("Could not find referral URL in output")
        }

        // Try to extract pass count (optional)
        let passesCount = extractPassesCount(clean)

        return ClaudePass(passesRemaining: passesCount, referralURL: referralURL)
    }

    // MARK: - Parsing Helpers

    internal static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    /// Extracts the passes count from text like "Guest passes · 3 left" or "3 left"
    internal static func extractPassesCount(_ text: String) -> Int? {
        // Pattern: digit(s) followed by "left"
        let pattern = #"(\d+)\s*left"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let countRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[countRange])
    }

    /// Extracts the referral URL from text
    internal static func extractReferralURL(_ text: String) -> URL? {
        // Pattern: https://claude.ai/referral/...
        let pattern = #"https://claude\.ai/referral/[A-Za-z0-9_-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let urlRange = Range(match.range, in: text) else {
            return nil
        }
        return URL(string: String(text[urlRange]))
    }

    // MARK: - Helpers

    private func probeWorkingDirectory() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = base
            .appendingPathComponent("ClaudeBar", isDirectory: true)
            .appendingPathComponent("Probe", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
