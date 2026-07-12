import Foundation
import Domain

/// Infrastructure adapter that probes the Oh My Pi CLI (`omp`) for usage quotas.
///
/// Oh My Pi is a coding-agent harness that manages OAuth accounts for multiple
/// upstream providers (Anthropic, OpenAI Codex, Z.ai, ...). `omp usage --json`
/// reports the rate-limit windows for every authenticated account:
///
/// ```json
/// {
///   "generatedAt": 1783869272381,
///   "reports": [
///     {
///       "provider": "anthropic",
///       "limits": [
///         {
///           "label": "Claude 5 Hour",
///           "scope": { "provider": "anthropic", "windowId": "5h" },
///           "window": { "id": "5h", "durationMs": 18000000, "resetsAt": 1783885200000 },
///           "amount": { "usedFraction": 0.08, "remainingFraction": 0.92, "unit": "percent" }
///         }
///       ],
///       "metadata": { "email": "user@example.com" }
///     }
///   ]
/// }
/// ```
///
/// Every limit becomes one `UsageQuota` labeled `"<Provider> [Tier] <window>"`
/// (e.g. "Claude 5h", "Codex Spark 7d"), so the card shows the headroom of
/// every account the harness can rotate through.
public struct OmpUsageProbe: UsageProbe {
    static let providerId = "omp"

    private let ompBinary: String
    private let timeout: TimeInterval
    private let cliExecutor: CLIExecutor

    public init(
        ompBinary: String = "omp",
        timeout: TimeInterval = 30.0,
        cliExecutor: CLIExecutor? = nil
    ) {
        self.ompBinary = ompBinary
        self.timeout = timeout
        self.cliExecutor = cliExecutor ?? SimpleCLIExecutor()
    }

    public func isAvailable() async -> Bool {
        if cliExecutor.locate(ompBinary) != nil {
            return true
        }
        AppLog.probes.error("Oh My Pi binary '\(ompBinary)' not found in PATH")
        return false
    }

    public func probe() async throws -> UsageSnapshot {
        guard cliExecutor.locate(ompBinary) != nil else {
            throw ProbeError.cliNotFound(ompBinary)
        }

        AppLog.probes.info("Starting Oh My Pi probe with `omp usage --json`...")

        let result: CLIResult
        do {
            result = try cliExecutor.execute(
                binary: ompBinary,
                args: ["usage", "--json"],
                input: nil,
                timeout: timeout,
                workingDirectory: nil,
                autoResponses: [:]
            )
        } catch let error as ProbeError {
            throw error
        } catch {
            AppLog.probes.error("Oh My Pi probe failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            // Never surface raw CLI output: usage output carries account
            // emails/ids, and this message reaches the UI via `lastError`.
            throw ProbeError.executionFailed("omp usage exited with code \(result.exitCode)")
        }

        let snapshot = try Self.parse(result.output)

        AppLog.probes.info("Oh My Pi probe success: \(snapshot.quotas.count) quotas found")

        return snapshot
    }

    // MARK: - Static Parsing (for testability)

    /// Parses `omp usage --json` output into a UsageSnapshot.
    ///
    /// The command prints a single JSON object; stray status lines around it
    /// (or stderr noise appended by the executor) are tolerated by slicing
    /// from the first `{` to the last `}`.
    public static func parse(_ text: String) throws -> UsageSnapshot {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else {
            throw ProbeError.parseFailed("No JSON object in omp usage output")
        }
        return try parseResponse(Data(text[start...end].utf8))
    }

    /// Parses the raw JSON payload into a UsageSnapshot.
    static func parseResponse(_ data: Data) throws -> UsageSnapshot {
        let payload: UsagePayload
        do {
            payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Malformed omp usage JSON: \(error.localizedDescription)")
        }

        // Multiple accounts on the same upstream provider need a discriminator
        // so labels — and therefore persisted quota keys, which the UI also
        // uses as stable identifiers — stay unique.
        var providerReportCounts: [String: Int] = [:]
        for report in payload.reports {
            providerReportCounts[report.provider, default: 0] += 1
        }

        var quotas: [UsageQuota] = []
        var seenLabels: Set<String> = []
        var accountRows: [ExtensionMetric] = []
        var seenRowLabels: Set<String> = []

        for (index, report) in payload.reports.enumerated() {
            let needsDiscriminator = providerReportCounts[report.provider, default: 0] > 1
            let discriminator = needsDiscriminator
                ? (report.accountDiscriminator ?? "#\(index + 1)")
                : nil

            // Two meters can share one window on the same account (e.g. Z.ai
            // token and request quotas, both "5h") — qualify those with the
            // metered unit instead of degrading to a bare ordinal.
            let windowGroupCounts = Dictionary(grouping: report.limits, by: \.windowGroupKey)
                .mapValues(\.count)

            let quotaCountBefore = quotas.count

            for limit in report.limits {
                guard let percentRemaining = limit.percentRemaining else { continue }

                let needsMeter = windowGroupCounts[limit.windowGroupKey, default: 0] > 1
                var label = Self.quotaLabel(
                    upstreamProvider: report.provider,
                    limit: limit,
                    meter: needsMeter ? limit.meterName : nil,
                    discriminator: discriminator
                )
                // Final guard: whatever slips through still gets a unique key.
                if seenLabels.contains(label) {
                    var suffix = 2
                    while seenLabels.contains("\(label) (\(suffix))") { suffix += 1 }
                    label = "\(label) (\(suffix))"
                }
                seenLabels.insert(label)

                quotas.append(
                    UsageQuota(
                        percentRemaining: percentRemaining,
                        quotaType: .timeLimit(label),
                        providerId: providerId,
                        resetsAt: limit.resetDate,
                        windowDuration: limit.windowDurationSeconds
                    )
                )
            }

            if quotas.count == quotaCountBefore {
                // Some providers deliberately report zero limits (e.g. Ollama
                // has no standalone quota API) — a report exists, so the
                // account is absent from `accountsWithoutUsage`. Still list it.
                let identity = report.identityLabel ?? discriminator ?? "account \(index + 1)"
                accountRows.append(Self.accountRow(
                    label: Self.uniqueLabel(
                        "\(Self.upstreamDisplayName(report.provider)) · \(identity)",
                        seen: &seenRowLabels
                    )
                ))
            }
        }

        // Credentials the harness holds for usage-capable providers that
        // produced no attributable report (expired session, fetch failure).
        // Surface them as explicit "No usage reported" rows — never as fake
        // quotas — so the card covers the full credential pool, matching
        // `omp usage`'s own account listing.
        for account in payload.accountsWithoutUsage ?? [] {
            accountRows.append(Self.accountRow(
                label: Self.uniqueLabel(
                    "\(Self.upstreamDisplayName(account.provider)) · \(account.identityLabel)",
                    seen: &seenRowLabels
                )
            ))
        }

        guard !quotas.isEmpty || !accountRows.isEmpty else {
            throw ProbeError.noData
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date(),
            accountEmail: Self.singleDistinctEmail(in: payload),
            extensionMetrics: accountRows.isEmpty ? nil : accountRows
        )
    }

    /// Returns `label`, suffixed if needed so it is unique within `seen`.
    /// Row labels double as UI list identifiers and must never collide.
    private static func uniqueLabel(_ base: String, seen: inout Set<String>) -> String {
        var label = base
        if seen.contains(label) {
            var suffix = 2
            while seen.contains("\(label) (\(suffix))") { suffix += 1 }
            label = "\(label) (\(suffix))"
        }
        seen.insert(label)
        return label
    }

    /// A display row for an account that has no usable quota data.
    private static func accountRow(label: String) -> ExtensionMetric {
        ExtensionMetric(
            label: label,
            value: "No usage reported",
            unit: "",
            icon: "person.crop.circle.badge.questionmark"
        )
    }

    // MARK: - Label Building

    /// Builds a compact, unique quota label like "Claude 5h" or "Codex Spark 7d".
    /// Labels are purely presentational; pace math gets its window length
    /// from the payload's `window.durationMs` (see `UsageQuota.windowDuration`).
    static func quotaLabel(
        upstreamProvider: String,
        limit: UsageLimit,
        meter: String?,
        discriminator: String?
    ) -> String {
        var parts: [String] = [Self.upstreamDisplayName(upstreamProvider)]
        if let tier = limit.scope?.tier, !tier.isEmpty {
            parts.append(tier.capitalized)
        }
        if let meter, !meter.isEmpty {
            parts.append(meter)
        }
        parts.append(limit.windowToken)
        if let discriminator, !discriminator.isEmpty {
            parts.append("· \(discriminator)")
        }
        return parts.joined(separator: " ")
    }

    /// Maps Oh My Pi upstream provider ids to short display names.
    /// The cases cover every id omp v16.4.6's usage registry emits
    /// (`@oh-my-pi/pi-ai/src/usage/*`); unknown ids are title-cased.
    static func upstreamDisplayName(_ id: String) -> String {
        switch id {
        case "anthropic": return "Claude"
        case "openai-codex": return "Codex"
        case "zai": return "Z.ai"
        case "google-gemini-cli": return "Gemini"
        case "google-antigravity": return "Antigravity"
        case "github-copilot": return "Copilot"
        case "kimi-code": return "Kimi"
        case "minimax-code": return "MiniMax"
        case "minimax-code-cn": return "MiniMax CN"
        case "opencode-go": return "OpenCode Go"
        default:
            // Title-case unknown ids: "some-provider" → "Some Provider"
            return id.split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// The single distinct account email across all reports and unreported
    /// accounts, or nil when the harness spans several (no one email would
    /// be truthful).
    private static func singleDistinctEmail(in payload: UsagePayload) -> String? {
        var emails = Set(payload.reports.compactMap { $0.metadata?.email })
        emails.formUnion((payload.accountsWithoutUsage ?? []).compactMap(\.email))
        return emails.count == 1 ? emails.first : nil
    }

    // MARK: - JSON Payload Models

    struct UsagePayload: Decodable {
        let reports: [UsageReport]
        let accountsWithoutUsage: [UnreportedAccount]?
    }

    /// A stored credential for a usage-capable provider that produced no
    /// attributable usage report (`accountsWithoutUsage` in the payload).
    struct UnreportedAccount: Decodable {
        let provider: String
        let type: String?
        let email: String?
        let accountId: String?
        let projectId: String?
        let enterpriseUrl: String?

        /// Mirrors `omp usage`'s own labeling of accounts without usage.
        var identityLabel: String {
            if type == "api_key" { return "API key" }
            for value in [email, accountId, projectId, enterpriseUrl] {
                if let value, !value.isEmpty { return value }
            }
            return "OAuth account"
        }
    }

    struct UsageReport: Decodable {
        let provider: String
        let limits: [UsageLimit]
        let metadata: ReportMetadata?

        /// Full identity of this account, mirroring `omp usage`'s own
        /// `reportAccountLabel`: metadata email → accountId → projectId,
        /// then any limit's scoped accountId/projectId (Gemini/Kimi carry
        /// identity in limit scopes rather than metadata).
        var identityLabel: String? {
            for value in [metadata?.email, metadata?.accountId, metadata?.projectId] {
                if let value, !value.isEmpty { return value }
            }
            for limit in limits {
                if let scoped = limit.scope?.accountId ?? limit.scope?.projectId, !scoped.isEmpty {
                    return scoped
                }
            }
            return nil
        }

        /// A short, stable token for quota-label discrimination: the email
        /// local part, or a prefix of whatever identity the report carries.
        var accountDiscriminator: String? {
            guard let identity = identityLabel else { return nil }
            let localPart = identity.split(separator: "@").first ?? Substring(identity)
            if localPart.count < identity.count {
                return String(localPart.prefix(16))
            }
            return String(identity.prefix(8))
        }
    }

    struct ReportMetadata: Decodable {
        let email: String?
        let accountId: String?
        let projectId: String?
        let planType: String?
    }

    struct UsageLimit: Decodable {
        let id: String?
        let label: String?
        let scope: LimitScope?
        let window: LimitWindow?
        let amount: LimitAmount?

        /// Percent of this window still remaining, preferring explicit
        /// fractions over derived used/limit math.
        var percentRemaining: Double? {
            if let remaining = amount?.remainingFraction {
                return remaining * 100
            }
            if let used = amount?.usedFraction {
                return (1 - used) * 100
            }
            if let used = amount?.used, let limit = amount?.limit, limit > 0 {
                return (limit - used) / limit * 100
            }
            return nil
        }

        /// When this window resets (epoch milliseconds → Date).
        var resetDate: Date? {
            guard let ms = window?.resetsAt else { return nil }
            return Date(timeIntervalSince1970: ms / 1000)
        }

        /// The window length in seconds, when reported.
        var windowDurationSeconds: TimeInterval? {
            guard let ms = window?.durationMs, ms > 0 else { return nil }
            return ms / 1000
        }

        /// Compact window token like "5h", "7d", "1w", "1mo".
        var windowToken: String {
            scope?.windowId ?? window?.id ?? window?.label ?? "limit"
        }

        /// Groups limits that share a (tier, window) on one account, so
        /// multi-meter windows can be told apart in labels.
        var windowGroupKey: String {
            "\(scope?.tier ?? "")|\(windowToken)"
        }

        /// Display name of the metered resource when it isn't the default
        /// percent meter (e.g. "Tokens", "Requests").
        var meterName: String? {
            guard let unit = amount?.unit, !unit.isEmpty,
                  unit.caseInsensitiveCompare("percent") != .orderedSame
            else { return nil }
            return unit.capitalized
        }
    }

    struct LimitScope: Decodable {
        let provider: String?
        let accountId: String?
        let projectId: String?
        let tier: String?
        let windowId: String?
    }

    struct LimitWindow: Decodable {
        let id: String?
        let label: String?
        let durationMs: Double?
        let resetsAt: Double?
    }

    struct LimitAmount: Decodable {
        let used: Double?
        let limit: Double?
        let remaining: Double?
        let usedFraction: Double?
        let remainingFraction: Double?
        let unit: String?
    }
}
