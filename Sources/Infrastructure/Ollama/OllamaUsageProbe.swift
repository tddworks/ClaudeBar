import Foundation
import Domain

// MARK: - Ollama API Probe

/// Probes the Ollama Cloud usage endpoint using a Bearer API key.
///
/// Ollama Pro / Ollama Cloud is a paid subscription on `ollama.com` (distinct
/// from the open-source local-only Ollama runtime). Users with the paid plan
/// can issue an API key from `https://ollama.com/settings/keys` and set it
/// via either:
///
/// - the `OLLAMA_API_KEY` (or `OLLAMA_KEY`) environment variable, OR
/// - the **API KEY** field in ClaudeBar's Settings UI.
///
/// The probe is "available" whenever an API key is resolvable; it does not
/// require any local CLI install.
///
/// ## Note on the endpoint
///
/// At the time of writing, Ollama Cloud does not expose a dedicated public
/// usage-JSON endpoint. We use `/api/tags` (the standard model-list endpoint)
/// as a connectivity probe; reaching it confirms the key is valid and lets
/// the snapshot surface "logged in via API key" identity info in the UI.
/// Once Ollama publishes a real usage endpoint, switch the URL here and
/// extend `parseUsageResponse(_:)` to populate session/weekly quotas.
public struct OllamaUsageProbe: UsageProbe {
    /// The default Ollama Cloud API host.
    public static let defaultBaseURL = URL(string: "https://ollama.com")!

    /// Names of environment variables consulted for the API key, in order.
    public static let apiKeyEnvironmentKeys = ["OLLAMA_API_KEY", "OLLAMA_KEY"]

    private let networkClient: any NetworkClient
    private let settingsRepository: any OllamaSettingsRepository
    private let environment: [String: String]
    private let baseURL: URL
    private let timeout: TimeInterval

    /// Creates an Ollama API probe.
    /// - Parameters:
    ///   - networkClient: HTTP client (defaults to `URLSession.shared`).
    ///   - settingsRepository: Settings repository where the API key and
    ///     env-var-name override are persisted.
    ///   - environment: Process environment to consult for the API key.
    ///   - baseURL: API base URL (override for tests).
    ///   - timeout: Request timeout in seconds.
    public init(
        networkClient: any NetworkClient = URLSession.shared,
        settingsRepository: any OllamaSettingsRepository,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        baseURL: URL = OllamaUsageProbe.defaultBaseURL,
        timeout: TimeInterval = 20
    ) {
        self.networkClient = networkClient
        self.settingsRepository = settingsRepository
        self.environment = environment
        self.baseURL = baseURL
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        resolveAPIKey() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = resolveAPIKey() else {
            AppLog.probes.error("Ollama API: no API key resolvable (neither env var nor saved key)")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting Ollama API probe...")

        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeBar/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Ollama API request failed: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Ollama API request failed: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid HTTP response from Ollama API")
        }

        AppLog.probes.debug("Ollama API response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return try Self.parseUsageResponse(data, providerId: "ollama")
        case 401, 403:
            AppLog.probes.error("Ollama API: authentication failed (\(httpResponse.statusCode))")
            throw ProbeError.authenticationRequired
        case 429:
            AppLog.probes.error("Ollama API: rate limited (429)")
            throw ProbeError.rateLimited(retryAt: Date().addingTimeInterval(60))
        default:
            // Never log the raw response body — Ollama responses can embed
            // account email, plan name, session token IDs, etc. The status
            // code plus body length is enough signal for debugging (CodeRabbit
            // review on PR #197).
            AppLog.probes.error("Ollama API: HTTP \(httpResponse.statusCode) (\(data.count) bytes)")
            throw ProbeError.executionFailed("Ollama API returned HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - API Key Resolution

    /// Resolves the API key by checking, in order:
    /// 1. The custom environment variable name in Settings (if any).
    /// 2. The default env vars (`OLLAMA_API_KEY`, `OLLAMA_KEY`).
    /// 3. The API key saved via the Settings UI.
    private func resolveAPIKey() -> String? {
        let customVar = settingsRepository.ollamaAuthEnvVar().trimmingCharacters(in: .whitespacesAndNewlines)
        if !customVar.isEmpty, let value = cleaned(environment[customVar]) {
            return value
        }
        for key in Self.apiKeyEnvironmentKeys {
            if let value = cleaned(environment[key]) {
                return value
            }
        }
        return cleaned(settingsRepository.getOllamaApiKey())
    }

    private func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Response Parsing (static for testability)

    /// Parses the Ollama `/api/tags` response into a `UsageSnapshot`.
    ///
    /// `/api/tags` does not return quota numbers, so the resulting snapshot
    /// has an empty `quotas` array and a `loginMethod = "API key"` identity.
    /// The UI surfaces this as "API account, no quota data" — exactly the
    /// same shape we use for the Mistral provider, which also has no
    /// quota endpoint.
    ///
    /// TODO: When Ollama publishes a real usage endpoint, decode session
    /// (`primary`) and weekly (`secondary`) windows into `UsageQuota` values
    /// and update the URL constant above accordingly.
    public static func parseUsageResponse(_ data: Data, providerId: String) throws -> UsageSnapshot {
        // Validate that the response is JSON shaped like the tags endpoint;
        // anything else likely means we hit a login page or HTML error.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProbeError.parseFailed("Ollama API: response is not JSON")
        }

        let modelCount = (json["models"] as? [Any])?.count ?? 0
        AppLog.probes.info("Ollama API probe success: \(modelCount) models visible to this account")

        return UsageSnapshot(
            providerId: providerId,
            quotas: [],
            capturedAt: Date(),
            loginMethod: "API key"
        )
    }
}
