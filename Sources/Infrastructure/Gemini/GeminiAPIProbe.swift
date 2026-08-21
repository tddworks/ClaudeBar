import Foundation
import Domain

internal struct GeminiAPIProbe {
    private let homeDirectory: String
    private let timeout: TimeInterval
    private let networkClient: any NetworkClient
    private let cliExecutor: CLIExecutor
    private let clock: any Clock

    private static let quotaEndpoint = "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota"
    private static let credentialsPath = "/.gemini/oauth_creds.json"

    private let maxRetries: Int

    init(
        homeDirectory: String,
        timeout: TimeInterval,
        networkClient: any NetworkClient,
        maxRetries: Int = 3,
        cliExecutor: CLIExecutor = DefaultCLIExecutor(),
        clock: any Clock = SystemClock()
    ) {
        self.homeDirectory = homeDirectory
        self.timeout = timeout
        self.networkClient = networkClient
        self.maxRetries = maxRetries
        self.cliExecutor = cliExecutor
        self.clock = clock
    }

    func probe() async throws -> UsageSnapshot {
        do {
            return try await probeAPI()
        } catch ProbeError.authenticationRequired {
            AppLog.probes.info("Gemini: Token expired, attempting CLI refresh...")
            do {
                try await refreshTokenViaCLI()
            } catch ProbeError.cliNotFound {
                // If CLI is not available, we can't refresh - propagate original auth error
                AppLog.probes.warning("Gemini: CLI not available for token refresh, authentication required")
                throw ProbeError.authenticationRequired
            }
            AppLog.probes.info("Gemini: Retrying API probe after token refresh...")
            do {
                return try await probeAPI()
            } catch ProbeError.authenticationRequired {
                AppLog.probes.error("Gemini: API probe failed with authentication error even after token refresh")
                throw ProbeError.authenticationRequired
            } catch {
                AppLog.probes.error("Gemini: API probe failed after token refresh: \(error)")
                throw error
            }
        }
    }

    private func probeAPI() async throws -> UsageSnapshot {
        let creds = try loadCredentials()
        AppLog.probes.debug("Gemini credentials loaded, expiry: \(String(describing: creds.expiryDate))")

        guard let accessToken = creds.accessToken, !accessToken.isEmpty else {
            AppLog.probes.error("Gemini probe failed: no access token in credentials file")
            throw ProbeError.authenticationRequired
        }

        // Discover the Gemini project ID for accurate quota data
        // Uses retry logic to handle cold-start network delays
        let repository = GeminiProjectRepository(networkClient: networkClient, timeout: timeout, maxRetries: maxRetries)
        let projectId = await repository.fetchBestProject(accessToken: accessToken)?.projectId

        if projectId == nil {
            AppLog.probes.warning("Gemini: Project discovery failed, proceeding without project ID (quota may be less accurate)")
        } else {
            AppLog.probes.debug("Gemini: Using project ID \(projectId ?? "")")
        }

        guard let url = URL(string: Self.quotaEndpoint) else {
            throw ProbeError.executionFailed("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include project ID if discovered for accurate quota
        if let projectId {
            request.httpBody = Data("{\"project\": \"\(projectId)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Gemini API response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            AppLog.probes.error("Gemini probe failed: authentication required (401)")
            throw ProbeError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("Gemini probe failed: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Gemini API response: \(responseText)")
        }

        let snapshot = try mapToSnapshot(data)
        AppLog.probes.info("Gemini probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    /// Runs the Gemini CLI briefly to trigger OAuth token refresh.
    /// The CLI handles token refresh automatically when it starts up.
    private func refreshTokenViaCLI() async throws {
        guard cliExecutor.locate("gemini") != nil else {
            AppLog.probes.error("Gemini CLI not found, cannot refresh token")
            throw ProbeError.cliNotFound("gemini")
        }

        AppLog.probes.debug("Gemini: Running CLI to refresh OAuth token...")

        _ = try await cliExecutor.execute(
            binary: "gemini",
            args: [],
            input: "/quit\n",
            timeout: 15.0,
            workingDirectory: nil,
            autoResponses: [:]
        )

        try await clock.sleep(nanoseconds: 1_500_000_000)

        AppLog.probes.debug("Gemini: CLI token refresh completed")
    }

    private func mapToSnapshot(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(QuotaResponse.self, from: data)

        guard let buckets = response.buckets, !buckets.isEmpty else {
            AppLog.probes.error("Gemini parse failed: no quota buckets in API response")
            throw ProbeError.parseFailed("No quota buckets in response")
        }

        // Group quotas by model, keeping lowest per model
        var modelQuotaMap: [String: (fraction: Double, resetTime: String?)] = [:]

        for bucket in buckets {
            guard let modelId = bucket.modelId, let fraction = bucket.remainingFraction else { continue }

            if let existing = modelQuotaMap[modelId] {
                if fraction < existing.fraction {
                    modelQuotaMap[modelId] = (fraction, bucket.resetTime)
                }
            } else {
                modelQuotaMap[modelId] = (fraction, bucket.resetTime)
            }
        }

        // Collapse aliases that share a quota bucket. The Code Assist API
        // exposes one tier-level quota under multiple model IDs (e.g. the Pro
        // tier appears as gemini-2.5-pro, gemini-3-pro-preview, and
        // gemini-3.1-pro-preview, all moving in lockstep). When the tier and
        // (fraction, resetTime) match, keep only the newest-versioned model
        // as the survivor — the menu otherwise shows the same quota three
        // times in a row. Models with no recognizable tier stay distinct.
        let dedupedEntries = Self.dedupeAliases(modelQuotaMap)

        // Sort by remaining fraction ascending (most-used models first), with
        // model ID as a stable tiebreaker so the order doesn't shuffle between
        // probes when multiple models share a quota (e.g. several at 100%).
        let quotas: [UsageQuota] = dedupedEntries
            .sorted { lhs, rhs in
                if lhs.fraction != rhs.fraction {
                    return lhs.fraction < rhs.fraction
                }
                return lhs.modelId < rhs.modelId
            }
            .map { entry in
                let resetsAt = entry.resetTime.flatMap { parseResetTime($0) }
                return UsageQuota(
                    percentRemaining: entry.fraction * 100,
                    quotaType: .modelSpecific(entry.displayLabel),
                    providerId: "gemini",
                    resetsAt: resetsAt,
                    resetText: formatResetText(resetsAt)
                )
            }

        guard !quotas.isEmpty else {
            AppLog.probes.error("Gemini parse failed: no valid quotas after processing buckets")
            throw ProbeError.parseFailed("No valid quotas found")
        }

        return UsageSnapshot(
            providerId: "gemini",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Credentials & Models

    private struct OAuthCredentials {
        let accessToken: String?
        let refreshToken: String?
        let expiryDate: Date?
    }

    private func loadCredentials() throws -> OAuthCredentials {
        let credsURL = URL(fileURLWithPath: homeDirectory + Self.credentialsPath)

        guard FileManager.default.fileExists(atPath: credsURL.path) else {
            AppLog.probes.error("Gemini probe failed: credentials file not found")
            throw ProbeError.authenticationRequired
        }

        let data = try Data(contentsOf: credsURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            AppLog.probes.error("Gemini probe failed: invalid JSON in credentials file")
            throw ProbeError.parseFailed("Invalid credentials file")
        }

        let accessToken = json["access_token"] as? String
        let refreshToken = json["refresh_token"] as? String

        var expiryDate: Date?
        if let expiryMs = json["expiry_date"] as? Double {
            expiryDate = Date(timeIntervalSince1970: expiryMs / 1000)
        }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiryDate: expiryDate
        )
    }

    // MARK: - Reset Time Parsing

    private func parseResetTime(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }

        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func formatResetText(_ date: Date?) -> String? {
        guard let date else { return nil }

        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return nil }

        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Resets in \(minutes)m"
        } else {
            return "Resets soon"
        }
    }

    private struct QuotaBucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelId: String?
        let tokenType: String?
    }

    private struct QuotaResponse: Decodable {
        let buckets: [QuotaBucket]?
    }

    // MARK: - Tier-aware Alias Dedupe

    fileprivate struct DedupedEntry {
        /// The model ID that won the survivor selection (kept for stable
        /// sort tiebreaks and parity with single-row entries).
        let modelId: String
        /// What gets shown to the user. For tiered entries this is the
        /// tier label ("Pro" / "Flash" / "Flash Lite") matching gemini-cli's
        /// own /model UI; for unrecognized models it's the modelId.
        let displayLabel: String
        let fraction: Double
        let resetTime: String?
    }

    /// Human-readable tier label matching gemini-cli's `/model` view.
    fileprivate static func tierDisplayLabel(_ tier: String) -> String {
        switch tier {
        case "pro": return "Pro"
        case "flash": return "Flash"
        case "flash-lite": return "Flash Lite"
        default: return tier
        }
    }

    /// Detects which tier a Gemini model ID belongs to. The Code Assist quota
    /// system gates on tier (Pro / Flash / Flash-Lite) but exposes the same
    /// bucket under every model alias the user is allowed to call. Returns nil
    /// for models with no recognizable tier — those keep their own row.
    /// Note: Flash-Lite must be checked before Flash (the substring "flash"
    /// appears in both).
    fileprivate static func tier(for modelId: String) -> String? {
        let lower = modelId.lowercased()
        if lower.contains("flash-lite") { return "flash-lite" }
        if lower.contains("flash") { return "flash" }
        if lower.contains("pro") { return "pro" }
        return nil
    }

    /// Extracts a comparable version score from a Gemini model ID. The version
    /// segment is the first dotted-number group after the "gemini-" prefix —
    /// e.g. "gemini-3.1-pro-preview" → 3.1, "gemini-2.5-flash" → 2.5.
    fileprivate static func versionScore(_ modelId: String) -> Double {
        let stripped = modelId.lowercased()
            .replacingOccurrences(of: "gemini-", with: "")
        guard let head = stripped.split(separator: "-").first else { return 0 }
        let nums = head.split(separator: ".").compactMap { Double($0) }
        guard let major = nums.first else { return 0 }
        let minor = nums.count > 1 ? nums[1] : 0
        return major + minor / 100.0
    }

    /// Decides which alias label survives when two share a tier+bucket. The
    /// stable model the user actually invokes day-to-day wins over preview
    /// IDs that share the same quota; among models of the same preview-ness
    /// the highest version wins. Falls back to model ID for stability.
    fileprivate static func isPreferredOver(_ candidate: String, _ existing: String) -> Bool {
        let candidatePreview = candidate.lowercased().contains("preview")
        let existingPreview = existing.lowercased().contains("preview")
        if candidatePreview != existingPreview { return !candidatePreview }
        let candidateScore = versionScore(candidate)
        let existingScore = versionScore(existing)
        if candidateScore != existingScore { return candidateScore > existingScore }
        return candidate < existing
    }

    fileprivate static func dedupeAliases(
        _ modelQuotaMap: [String: (fraction: Double, resetTime: String?)]
    ) -> [DedupedEntry] {
        struct BucketKey: Hashable {
            let group: String     // "tier:pro" or "model:<id>"
            let fraction: Double
            let resetTime: String?
        }

        var survivors: [BucketKey: DedupedEntry] = [:]
        for (modelId, data) in modelQuotaMap {
            let detectedTier = tier(for: modelId)
            let group = detectedTier.map { "tier:\($0)" } ?? "model:\(modelId)"
            let key = BucketKey(group: group, fraction: data.fraction, resetTime: data.resetTime)
            let displayLabel = detectedTier.map(tierDisplayLabel) ?? modelId

            if let existing = survivors[key] {
                if isPreferredOver(modelId, existing.modelId) {
                    survivors[key] = DedupedEntry(modelId: modelId, displayLabel: displayLabel, fraction: data.fraction, resetTime: data.resetTime)
                }
            } else {
                survivors[key] = DedupedEntry(modelId: modelId, displayLabel: displayLabel, fraction: data.fraction, resetTime: data.resetTime)
            }
        }
        return Array(survivors.values)
    }
}
