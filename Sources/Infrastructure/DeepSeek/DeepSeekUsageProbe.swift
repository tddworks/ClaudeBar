import Foundation
import Domain

/// Probes the DeepSeek API for balance information.
/// DeepSeek is pay-per-use and exposes no percentage/window quota — only a
/// monetary balance via `GET https://api.deepseek.com/user/balance`.
/// Authentication: Bearer token from env var or stored API key.
public struct DeepSeekUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any DeepSeekSettingsRepository
    private let timeout: TimeInterval
    /// Reads an environment variable by name. Injected so tests are
    /// deterministic regardless of the host environment.
    private let environmentValue: @Sendable (String) -> String?

    /// The DeepSeek balance endpoint
    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any DeepSeekSettingsRepository,
        timeout: TimeInterval = 30,
        environmentValue: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
        self.environmentValue = environmentValue
    }

    // MARK: - Token Resolution

    func getApiKey() -> String? {
        // First, check environment variable if configured
        let envVarName = settingsRepository.deepseekAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "DEEPSEEK_API_KEY" : envVarName
        if let envValue = environmentValue(effectiveEnvVar), !envValue.isEmpty {
            AppLog.probes.debug("DeepSeek: Using API key from env var '\(effectiveEnvVar)'")
            return envValue
        }

        // Fall back to stored API key
        if let storedKey = settingsRepository.getDeepSeekApiKey(), !storedKey.isEmpty {
            AppLog.probes.debug("DeepSeek: Using stored API key")
            return storedKey
        }

        return nil
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasKey = getApiKey() != nil
        if !hasKey {
            AppLog.probes.debug("DeepSeek: Not available - no API key configured")
        }
        return hasKey
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = getApiKey(), !apiKey.isEmpty else {
            AppLog.probes.error("DeepSeek: No API key configured (check env var or settings)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting DeepSeek probe...")

        var request = URLRequest(url: Self.balanceURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("DeepSeek API returned HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProbeError.authenticationRequired
            }
            throw ProbeError.executionFailed("DeepSeek API returned HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("DeepSeek API response: \(responseText.prefix(500))")
        }

        let snapshot = try Self.parseResponse(data, providerId: "deepseek")

        AppLog.probes.info("DeepSeek probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(quota.formattedDollarRemaining ?? "n/a") remaining")
        }

        return snapshot
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the DeepSeek user balance response into a UsageSnapshot.
    /// DeepSeek reports a monetary balance with no percentage cap, so the quota
    /// uses `dollarRemaining` with `percentRemaining` pinned to 100 (AmpCode pattern).
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response: DeepSeekBalanceResponse
        do {
            response = try decoder.decode(DeepSeekBalanceResponse.self, from: data)
        } catch {
            AppLog.probes.error("DeepSeek parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("DeepSeek raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        let balanceInfos = response.balanceInfos ?? []

        guard !balanceInfos.isEmpty else {
            AppLog.probes.error("DeepSeek: Empty balance_infos in response")
            throw ProbeError.noData
        }

        // Use the account's primary balance entry. DeepSeek returns the billing
        // currency first (e.g. CNY for Chinese accounts); preferring USD would
        // mislabel those balances as USD.
        let selected = balanceInfos[0]

        let posixLocale = Locale(identifier: "en_US_POSIX")
        guard let total = Decimal(string: selected.totalBalance, locale: posixLocale) else {
            throw ProbeError.parseFailed("Invalid total_balance: \(selected.totalBalance)")
        }
        let granted = selected.grantedBalance.flatMap { Decimal(string: $0, locale: posixLocale) }
        let toppedUp = selected.toppedUpBalance.flatMap { Decimal(string: $0, locale: posixLocale) }

        // Balance has no cap → percent is 100 when available. When DeepSeek
        // reports is_available == false, the balance can't be used for API
        // calls, so surface the quota as depleted.
        let percentRemaining: Double = response.isAvailable == false ? 0 : 100
        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: .modelSpecific("Balance"),
            providerId: providerId,
            resetText: breakdownText(granted: granted, toppedUp: toppedUp, currency: selected.currency),
            dollarRemaining: total,
            currency: selected.currency
        )

        return UsageSnapshot(
            providerId: providerId,
            quotas: [quota],
            capturedAt: Date()
        )
    }

    // MARK: - Formatting

    /// Builds the "Paid: $30.00 · Granted: $10.00" breakdown subtitle,
    /// using the balance's currency symbol (e.g. ¥ for CNY).
    static func breakdownText(granted: Decimal?, toppedUp: Decimal?, currency: String) -> String? {
        var parts: [String] = []
        if let toppedUp {
            parts.append("Paid: \(formatAmount(toppedUp, currency: currency))")
        }
        if let granted {
            parts.append("Granted: \(formatAmount(granted, currency: currency))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func formatAmount(_ amount: Decimal, currency: String) -> String {
        String(
            format: "%@%.2f",
            UsageQuota.currencySymbol(for: currency),
            NSDecimalNumber(decimal: amount).doubleValue
        )
    }
}

// MARK: - Response Models (Internal)

struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool?
    let balanceInfos: [DeepSeekBalanceInfo]?
}

struct DeepSeekBalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String?
    let toppedUpBalance: String?
}
