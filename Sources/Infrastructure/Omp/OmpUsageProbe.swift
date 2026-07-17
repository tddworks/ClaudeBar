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
        var seenGroupTitles: Set<String> = []

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
            let accountRowCountBefore = accountRows.count

            let providerName = Self.upstreamDisplayName(report.provider)
            let group = discriminator.map { "\(providerName) · \($0)" } ?? providerName

            for limit in report.limits {
                if let dollarUsed = limit.uncappedMonetaryUsed {
                    accountRows.append(Self.uncappedSpendRow(
                        upstreamProvider: report.provider,
                        limit: limit,
                        dollarUsed: dollarUsed,
                        discriminator: discriminator,
                        group: group,
                        seenLabels: &seenRowLabels
                    ))
                    continue
                }

                let monetaryAmounts = limit.cappedMonetaryAmounts
                if limit.isMonetary, monetaryAmounts == nil {
                    continue
                }
                guard let percentRemaining = limit.percentRemaining else { continue }

                let needsMeter = windowGroupCounts[limit.windowGroupKey, default: 0] > 1
                let meter = needsMeter ? limit.meterName : nil
                var label = Self.quotaLabel(
                    upstreamProvider: report.provider,
                    limit: limit,
                    meter: meter,
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
                        windowDuration: limit.windowDurationSeconds,
                        dollarUsed: monetaryAmounts?.used,
                        dollarCap: monetaryAmounts?.cap,
                        group: group,
                        compactTitle: Self.compactTitle(limit: limit, meter: meter, providerName: providerName)
                    )
                )
            }

            if quotas.count > quotaCountBefore || accountRows.count > accountRowCountBefore {
                // Reserve the emitted quota-group title so a later note
                // section can never silently collide with it.
                seenGroupTitles.insert(group)
            } else {
                // Some providers deliberately report zero limits (e.g. Ollama
                // has no standalone quota API) — a report exists, so the
                // account is absent from `accountsWithoutUsage`. Still list it.
                let identity = report.identityLabel ?? discriminator ?? "account \(index + 1)"
                accountRows.append(Self.accountRow(
                    label: Self.uniqueLabel(
                        "\(providerName) · \(identity)",
                        seen: &seenRowLabels
                    ),
                    group: Self.uniqueLabel(
                        "\(providerName) · \(Self.shortIdentity(identity))",
                        seen: &seenGroupTitles
                    )
                ))
            }
        }

        // Credentials the harness holds for usage-capable providers that
        // produced no attributable report (expired session, fetch failure).
        // Surface genuinely unmatched credentials as explicit
        // "No usage reported" rows — never as fake quotas.
        var emittedUnreportedAccounts: [UnreportedAccount] = []
        for account in payload.accountsWithoutUsage ?? [] {
            let matchesReport = payload.reports.contains { report in
                Self.emailOrAccountIdMatch(
                    provider: account.provider,
                    email: account.email,
                    accountId: account.accountId,
                    orgId: account.orgId,
                    otherProvider: report.provider,
                    otherEmail: report.metadata?.email,
                    otherAccountId: report.matchableAccountId
                )
            }
            let duplicatesRow = emittedUnreportedAccounts.contains { emitted in
                guard !Self.hasOrganization(emitted.orgId) else { return false }
                return Self.emailOrAccountIdMatch(
                    provider: account.provider,
                    email: account.email,
                    accountId: account.accountId,
                    orgId: account.orgId,
                    otherProvider: emitted.provider,
                    otherEmail: emitted.email,
                    otherAccountId: emitted.accountId
                )
            }
            guard !matchesReport, !duplicatesRow else { continue }

            emittedUnreportedAccounts.append(account)
            let providerName = Self.upstreamDisplayName(account.provider)
            accountRows.append(Self.accountRow(
                label: Self.uniqueLabel(
                    "\(providerName) · \(account.identityLabel)",
                    seen: &seenRowLabels
                ),
                group: Self.uniqueLabel(
                    "\(providerName) · \(Self.shortIdentity(account.identityLabel))",
                    seen: &seenGroupTitles
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

    /// Provider-scoped identity match for defensively omitting only org-less
    /// stale credential rows. Org-scoped credentials represent distinct limit
    /// pools and remain visible even when an email or account id matches.
    /// For org-less rows, normalized email is authoritative when both sides
    /// have one; exact account id is the fallback when either email is absent.
    private static func emailOrAccountIdMatch(
        provider: String,
        email: String?,
        accountId: String?,
        orgId: String?,
        otherProvider: String,
        otherEmail: String?,
        otherAccountId: String?
    ) -> Bool {
        guard provider == otherProvider else { return false }
        guard !Self.hasOrganization(orgId) else { return false }

        if let email = Self.normalizedEmail(email),
           let otherEmail = Self.normalizedEmail(otherEmail) {
            return email == otherEmail
        }

        guard let accountId, !accountId.isEmpty,
              let otherAccountId, !otherAccountId.isEmpty else {
            return false
        }
        return accountId == otherAccountId
    }

    private static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func hasOrganization(_ orgId: String?) -> Bool {
        guard let orgId else { return false }
        return !orgId.isEmpty
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

    /// A display row for an account that has no usable quota data; `group`
    /// places it under its own account section in grouped rendering.
    private static func accountRow(label: String, group: String) -> ExtensionMetric {
        ExtensionMetric(
            label: label,
            value: "No usage reported",
            unit: "",
            icon: "person.crop.circle.badge.questionmark",
            group: group
        )
    }

    /// A note row for an uncapped monetary meter. It intentionally does not
    /// fabricate a percentage-based quota.
    private static func uncappedSpendRow(
        upstreamProvider: String,
        limit: UsageLimit,
        dollarUsed: Decimal,
        discriminator: String?,
        group: String,
        seenLabels: inout Set<String>
    ) -> ExtensionMetric {
        var labelParts = [upstreamDisplayName(upstreamProvider), limit.labelToken, "Usage"]
        if let discriminator, !discriminator.isEmpty {
            labelParts.append("· \(discriminator)")
        }

        return ExtensionMetric(
            label: uniqueLabel(labelParts.joined(separator: " "), seen: &seenLabels),
            value: "\(limit.labelToken) usage \(formatMoney(dollarUsed)) spent · no cap",
            unit: "",
            icon: "dollarsign.circle",
            group: group
        )
    }

    private static func formatMoney(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "$\(value)"
    }

    /// Shortens an account identity for section headers: the email local
    /// part, or a prefix of opaque ids — mirroring quota discriminators.
    static func shortIdentity(_ identity: String) -> String {
        let localPart = identity.split(separator: "@").first ?? Substring(identity)
        if localPart.count < identity.count {
            return String(localPart.prefix(16))
        }
        return String(identity.prefix(16))
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
        parts.append(limit.labelToken)
        if let discriminator, !discriminator.isEmpty {
            parts.append("· \(discriminator)")
        }
        return parts.joined(separator: " ")
    }

    /// Builds the short in-section card title (e.g. "5h", "Spark 7d",
    /// "Tokens 5h") — the provider/account context lives in the section
    /// header (`UsageQuota.group`), so it is not repeated per card.
    /// Purely presentational: quota labels and persisted quota keys keep
    /// the raw window token (see `UsageQuota.compactTitle`).
    static func compactTitle(limit: UsageLimit, meter: String?, providerName: String) -> String {
        var parts: [String] = []
        if let tier = limit.scope?.tier, !tier.isEmpty {
            parts.append(tier.capitalized)
        }
        // Monetary rows keep their spend-oriented `labelToken` contract
        // ("Extra", "Monthly", "Spend") — window humanization only applies
        // to window/rate meters.
        if limit.isMonetary {
            if let meter, !meter.isEmpty {
                parts.append(meter)
            }
            parts.append(limit.labelToken)
            return parts.joined(separator: " ")
        }
        let display = limit.displayWindowToken(providerName: providerName)
        // A label-derived token already names the metered resource
        // ("Premium Requests"); prefixing the meter would duplicate it.
        if let meter, !meter.isEmpty, !display.selfDescribing {
            parts.append(meter)
        }
        parts.append(display.token)
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
        let orgId: String?
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

        /// Account identity used for exact matching. Some providers place it
        /// on limit scopes; project ids remain deliberately excluded.
        var matchableAccountId: String? {
            if let accountId = metadata?.accountId, !accountId.isEmpty {
                return accountId
            }
            for limit in limits {
                if let accountId = limit.scope?.accountId, !accountId.isEmpty {
                    return accountId
                }
            }
            return nil
        }

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

        var isMonetary: Bool {
            amount?.unit?.caseInsensitiveCompare("usd") == .orderedSame
        }

        var cappedMonetaryAmounts: (used: Decimal, cap: Decimal)? {
            guard isMonetary,
                  let rawLimit = amount?.limit, rawLimit > 0,
                  let used = amount?.roundedUsed,
                  let cap = amount?.roundedLimit
            else { return nil }
            return (used, cap)
        }

        var uncappedMonetaryUsed: Decimal? {
            guard isMonetary, amount?.limit == nil else { return nil }
            return amount?.roundedUsed
        }

        /// Monetary rows get a spend-oriented token without changing
        /// `windowToken`, which remains the grouping key for all meters.
        var labelToken: String {
            guard isMonetary else { return windowToken }
            let token = scope?.windowId ?? window?.id ?? "spend"
            return token.prefix(1).uppercased() + token.dropFirst()
        }

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
                let fraction = (limit - used) / limit * 100
                return NSDecimalNumber(decimal: fraction).doubleValue
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
        ///
        /// This raw chain is identity: it feeds quota labels (persisted
        /// quota keys) and meter-qualification grouping, so it is never
        /// humanized — display cleanup lives in `displayWindowToken`.
        var windowToken: String {
            scope?.windowId ?? window?.id ?? window?.label ?? "limit"
        }

        /// Card-title token plus whether it already describes the metered
        /// resource on its own (label-derived tokens do; machine tokens
        /// need the meter prefix when several meters share one window).
        struct DisplayWindowToken {
            let token: String
            let selfDescribing: Bool
        }

        /// Humanized token for the in-section card title.
        ///
        /// Some reporters emit machine window ids next to human labels
        /// (Kimi's 5-hour rate limit arrives as `300time_unit_minute` with
        /// label "5h limit"; its summary row is `default` with label
        /// "Total quota"). Prefer, in order: an already-compact id, a token
        /// derived from the window duration, the limit's own label, the
        /// window label, the raw id. Label-derived tokens drop a leading
        /// provider name (Gemini labels embed it) since the section header
        /// already carries that context.
        func displayWindowToken(providerName: String) -> DisplayWindowToken {
            let raw = scope?.windowId ?? window?.id
            if let raw, Self.isCompactWindowToken(raw) {
                return DisplayWindowToken(token: raw, selfDescribing: false)
            }
            if let seconds = windowDurationSeconds,
               let derived = Self.compactDurationToken(seconds) {
                return DisplayWindowToken(token: derived, selfDescribing: false)
            }
            if let label, !label.isEmpty {
                return DisplayWindowToken(
                    token: Self.strippingProviderPrefix(label, providerName: providerName),
                    selfDescribing: true
                )
            }
            if let windowLabel = window?.label, !windowLabel.isEmpty {
                return DisplayWindowToken(
                    token: Self.strippingProviderPrefix(windowLabel, providerName: providerName),
                    selfDescribing: true
                )
            }
            return DisplayWindowToken(token: raw ?? "limit", selfDescribing: false)
        }

        /// True for tokens that already read as a compact window ("5h",
        /// "7d", "1mo") and can go on a card verbatim.
        static func isCompactWindowToken(_ token: String) -> Bool {
            token.range(
                of: "^\\d{1,4}(s|m|h|d|w|mo|y)$",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }

        /// Formats a window length as its largest whole unit ("5h", "7d",
        /// "90m"); nil for non-positive lengths and for payload garbage
        /// (non-finite or Int-overflowing durations must degrade to the
        /// label fallback, never trap).
        static func compactDurationToken(_ seconds: TimeInterval) -> String? {
            guard let total = Int(exactly: seconds.rounded()), total > 0 else { return nil }
            if total % 86_400 == 0 { return "\(total / 86_400)d" }
            if total % 3_600 == 0 { return "\(total / 3_600)h" }
            if total % 60 == 0 { return "\(total / 60)m" }
            return "\(total)s"
        }

        /// Drops a leading "<providerName> " from a label-derived token —
        /// the section header already names the provider, and some
        /// reporters (Gemini) embed it in every limit label.
        static func strippingProviderPrefix(_ label: String, providerName: String) -> String {
            let trimmed = label.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > providerName.count + 1,
                  trimmed.lowercased().hasPrefix(providerName.lowercased() + " ")
            else { return trimmed }
            return String(trimmed.dropFirst(providerName.count + 1))
                .trimmingCharacters(in: .whitespaces)
        }

        /// Groups limits that share a (tier, window) on one account, so
        /// multi-meter windows can be told apart in labels.
        var windowGroupKey: String {
            "\(scope?.tier ?? "")|\(windowToken)"
        }

        /// Display name of the metered resource when it isn't the default
        /// percent meter (e.g. "Tokens", "Requests").
        var meterName: String? {
            guard !isMonetary,
                  let unit = amount?.unit, !unit.isEmpty,
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
        /// Monetary fields decode as `Decimal` straight from the JSON number
        /// token, so cent-boundary values like 1.005 never pick up binary
        /// floating-point error before rounding.
        let used: Decimal?
        let limit: Decimal?
        let remaining: Double?
        let usedFraction: Double?
        let remainingFraction: Double?
        let unit: String?

        var roundedUsed: Decimal? {
            Self.roundedMoney(used)
        }

        var roundedLimit: Decimal? {
            Self.roundedMoney(limit)
        }

        private static func roundedMoney(_ value: Decimal?) -> Decimal? {
            guard var decimal = value else { return nil }
            var rounded = Decimal()
            NSDecimalRound(&rounded, &decimal, 2, .plain)
            return rounded
        }
    }
}
