import Foundation
import Domain

/// Best-effort usage probe for Claude Desktop users, who have no Claude Code
/// CLI and therefore no data in CLI or API mode (issue #198).
///
/// Reads the daily token counter that Claude Desktop maintains at
/// `~/Library/Application Support/Claude/buddy-tokens.json`:
///
///     {"tokens-today": {"date": "2026-05-28", "tokens": 74422}}
///
/// The file is an implementation detail of Claude Desktop, so this probe is
/// deliberately defensive: any structural change to the file (missing keys,
/// new shape, unparseable values) fails with `ProbeError.parseFailed`, and a
/// counter whose date is not the user's *local* day is treated as no data
/// (`ProbeError.noData`) — yesterday's total must never render as today's
/// usage. File contents are never logged: the file log has no redaction, and
/// the data never leaves the machine.
///
/// Because the file carries a plain daily total — no session/weekly windows
/// and no cap — the snapshot carries the count as an extension metric card
/// ("Tokens Today") instead of a percentage quota like the CLI/API probes.
public struct ClaudeDesktopFileUsageProbe: UsageProbe, Sendable {
    /// Directory Claude Desktop keeps its support files in.
    private let claudeDir: URL
    /// The user's calendar — its timezone defines "today" for date validation.
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        claudeDir: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Claude"),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.claudeDir = claudeDir
        self.calendar = calendar
        self.now = now
    }

    /// Path to the buddy-tokens file (exposed for diagnostics, like
    /// `ClaudeCredentialLoader.credentialsFilePath`).
    public var buddyTokensFileURL: URL {
        claudeDir.appendingPathComponent("buddy-tokens.json")
    }

    public func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: buddyTokensFileURL.path)
    }

    public func probe() async throws -> UsageSnapshot {
        let currentDate = now()

        guard let data = try? Data(contentsOf: buddyTokensFileURL) else {
            AppLog.probes.info("Claude Desktop: no buddy-tokens.json at \(self.buddyTokensFileURL.path)")
            throw ProbeError.noData
        }

        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(BuddyTokensFile.self, from: data) else {
            // Not valid JSON at all vs. a changed schema — either way the
            // shape is unknown and nothing may be displayed. The reason is
            // structural only; it never quotes file contents.
            if Self.isValidJSONObject(data) {
                throw ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today'")
            }
            throw ProbeError.parseFailed("buddy-tokens.json is not valid JSON")
        }

        guard let entry = file.tokensToday else {
            throw ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today'")
        }

        guard entry.hasTokens else {
            throw ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today.tokens'")
        }

        guard let tokens = entry.tokens, tokens >= 0 else {
            throw ProbeError.parseFailed("buddy-tokens.json schema changed: invalid 'tokens' value")
        }

        guard let recordedDate = entry.date else {
            throw ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today.date'")
        }

        guard let parsedDate = Self.dayFormatter(calendar: calendar).date(from: recordedDate) else {
            throw ProbeError.parseFailed("buddy-tokens.json schema changed: invalid 'date' value")
        }

        // Only the counter for the user's local day is current. Anything else
        // (yesterday after midnight, or a clock-skewed future stamp) is stale
        // data that must not render as today's usage.
        guard calendar.isDate(parsedDate, inSameDayAs: currentDate) else {
            AppLog.probes.info("Claude Desktop: buddy-tokens.json is not from today — skipping stale data")
            throw ProbeError.noData
        }

        AppLog.probes.info("Claude Desktop: read today's token counter (\(tokens) tokens)")

        let metric = ExtensionMetric(
            label: "Tokens Today",
            value: Self.formattedTokenCount(tokens),
            unit: "tokens",
            icon: "number"
        )
        return UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: currentDate,
            extensionMetrics: [metric]
        )
    }

    // MARK: - Parsing

    private struct BuddyTokensFile: Decodable {
        let tokensToday: TokensToday?

        enum CodingKeys: String, CodingKey {
            case tokensToday = "tokens-today"
        }
    }

    private struct TokensToday: Decodable {
        /// Token counters are integers, but Claude Desktop may emit a
        /// fractional-tolerant number; decode any number and validate below.
        let tokens: Double?
        /// Distinguishes a missing `tokens` key (schema change) from a
        /// present-but-invalid value.
        let hasTokens: Bool
        let date: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case date
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // A non-string `date` is a schema change just like a missing one;
            // both decode to nil and surface as parseFailed downstream.
            date = (try? container.decodeIfPresent(String.self, forKey: .date)) ?? nil
            if container.contains(.tokens) {
                hasTokens = true
                if let intValue = try? container.decode(Int.self, forKey: .tokens) {
                    tokens = Double(intValue)
                } else {
                    tokens = try? container.decode(Double.self, forKey: .tokens)
                }
            } else {
                hasTokens = false
                tokens = nil
            }
        }
    }

    /// Strict `yyyy-MM-dd` parsing in the user's timezone (via the calendar),
    /// POSIX locale so the format never shifts with region settings.
    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func isValidJSONObject(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// Grouped decimal formatting ("74,422", "1,204,556") for the metric card.
    private static func formattedTokenCount(_ tokens: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(Int(tokens))"
    }
}
