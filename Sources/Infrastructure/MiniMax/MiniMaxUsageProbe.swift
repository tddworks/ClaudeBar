import Foundation
import Domain

/// Probes MiniMax Coding Plan API for usage quota information.
/// Supports both international (minimax.io) and China (minimaxi.com) regions.
/// (支持国际版和中国版两个区域)
/// Authentication: Bearer token from env var or stored API key.
public struct MiniMaxUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let settingsRepository: any MiniMaxSettingsRepository
    private let timeout: TimeInterval

    /// Resolves the API URL based on the configured region (根据区域配置动态选择 API URL)
    var apiURL: String {
        settingsRepository.minimaxRegion().codingPlanRemainsURL
    }

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any MiniMaxSettingsRepository,
        timeout: TimeInterval = 30
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.timeout = timeout
    }

    // MARK: - Token Resolution

    func getApiKey() -> String? {
        // First, check environment variable if configured
        let envVarName = settingsRepository.minimaxAuthEnvVar()
        let effectiveEnvVar = envVarName.isEmpty ? "MINIMAX_API_KEY" : envVarName
        if let envValue = ProcessInfo.processInfo.environment[effectiveEnvVar], !envValue.isEmpty {
            AppLog.probes.debug("MiniMax: Using API key from env var '\(effectiveEnvVar)'")
            return envValue
        }

        // Fall back to stored API key
        if let storedKey = settingsRepository.getMinimaxApiKey(), !storedKey.isEmpty {
            AppLog.probes.debug("MiniMax: Using stored API key")
            return storedKey
        }

        return nil
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let hasKey = getApiKey() != nil
        if !hasKey {
            AppLog.probes.debug("MiniMax: Not available - no API key configured")
        }
        return hasKey
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = getApiKey(), !apiKey.isEmpty else {
            AppLog.probes.error("MiniMax: No API key configured (check env var or settings)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting MiniMax probe...")

        guard let url = URL(string: apiURL) else {
            throw ProbeError.executionFailed("Invalid MiniMax API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            AppLog.probes.error("MiniMax API returned HTTP \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ProbeError.authenticationRequired
            }
            throw ProbeError.executionFailed("MiniMax API returned HTTP \(httpResponse.statusCode)")
        }

        // Log raw response at debug level
        if let responseText = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("MiniMax API response: \(responseText.prefix(500))")
        }

        let snapshot = try Self.parseResponse(data, providerId: "minimax")

        AppLog.probes.info("MiniMax probe success: \(snapshot.quotas.count) quotas found")
        for quota in snapshot.quotas {
            AppLog.probes.info("  - \(quota.quotaType.displayName): \(Int(quota.percentRemaining))% remaining")
        }

        return snapshot
    }

    // MARK: - Response Parsing (Static for testability)

    /// Parses the MiniMax Coding Plan remains API response into a UsageSnapshot
    static func parseResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response: MiniMaxRemainsResponse
        do {
            response = try decoder.decode(MiniMaxRemainsResponse.self, from: data)
        } catch {
            AppLog.probes.error("MiniMax parse failed: Invalid JSON - \(error.localizedDescription)")
            if let rawString = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("MiniMax raw response: \(rawString.prefix(500))")
            }
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        // Check API error status
        if response.baseResp.statusCode != 0 {
            let message = response.baseResp.statusMsg ?? "Unknown error"
            AppLog.probes.error("MiniMax API error: \(response.baseResp.statusCode) - \(message)")
            throw ProbeError.executionFailed("MiniMax API error: \(message)")
        }

        let modelRemains = response.modelRemains ?? []

        guard !modelRemains.isEmpty else {
            AppLog.probes.error("MiniMax: Empty model_remains in response")
            throw ProbeError.noData
        }

        let quotas = modelRemains.map { model -> UsageQuota in
            let legacyRemaining: Double? = {
                let total = model.currentIntervalTotalCount
                guard total > 0 else { return nil }
                let clampedRemaining = min(max(model.currentIntervalUsageCount, 0), total)
                return Double(clampedRemaining) / Double(total) * 100.0
            }()

            // Token Plan returns percentages directly. Older responses only
            // exposed counts, so keep that path for existing installations.
            let intervalRemaining = model.currentIntervalRemainingPercent.map(Self.clampPercentage) ?? legacyRemaining
            let weeklyRemaining = model.currentWeeklyRemainingPercent.map(Self.clampPercentage)
            let remaining = min(intervalRemaining ?? 0, weeklyRemaining ?? 100)

            let useWeeklyWindow = if let weeklyRemaining {
                weeklyRemaining < (intervalRemaining ?? 100)
            } else {
                false
            }
            let resetMilliseconds = useWeeklyWindow ? model.weeklyEndTime : model.endTime
            let windowDuration = useWeeklyWindow
                ? Self.windowDuration(start: model.weeklyStartTime, end: model.weeklyEndTime)
                : Self.windowDuration(start: model.startTime, end: model.endTime)
            let resetsAt = resetMilliseconds.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }

            let total = model.currentIntervalTotalCount
            let clampedRemaining = min(max(model.currentIntervalUsageCount, 0), max(total, 0))
            let usedCount = max(total - clampedRemaining, 0)
            let resetText = intervalRemaining != nil && model.currentIntervalRemainingPercent != nil
                ? "\(Int((100 - remaining).rounded()))% used"
                : "\(usedCount)/\(total) requests"

            return UsageQuota(
                percentRemaining: remaining,
                quotaType: .modelSpecific(model.modelName),
                providerId: providerId,
                resetsAt: resetsAt,
                resetText: resetText,
                windowDuration: windowDuration
            )
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: Date()
        )
    }

    private static func windowDuration(start: Int64?, end: Int64?) -> TimeInterval? {
        guard let start, let end, end > start else { return nil }
        return Double(end - start) / 1000.0
    }

    private static func clampPercentage(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

// MARK: - Response Models (Internal)

struct MiniMaxRemainsResponse: Decodable {
    let baseResp: BaseResp
    let modelRemains: [ModelRemain]?
}

struct BaseResp: Decodable {
    let statusCode: Int
    let statusMsg: String?
}

struct ModelRemain: Decodable {
    let modelName: String
    let currentIntervalTotalCount: Int
    let currentIntervalUsageCount: Int
    let currentIntervalRemainingPercent: Double?
    let currentWeeklyRemainingPercent: Double?
    let remainsTime: Int?
    let startTime: Int64?
    let endTime: Int64?
    let weeklyStartTime: Int64?
    let weeklyEndTime: Int64?
}
