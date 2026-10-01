import Foundation
import Domain

/// Google Cloud Code endpoints Antigravity uses for quota, reachable with the user's own OAuth
/// access token even when the desktop app is closed.
///
/// The stored token is used as-is: it is refreshed whenever Antigravity or `agy` runs, and this
/// client deliberately does not perform the OAuth refresh grant (that would require embedding
/// Antigravity's OAuth client credentials). An expired token surfaces as "sign in again".
///
/// Reverse-engineered from the Antigravity app; endpoints may change without notice.
struct AntigravityCloudCodeClient: Sendable {

    enum Outcome: Sendable {
        case ok(Data)
        /// 401/403 — the token was rejected; the same token will fail on any base URL.
        case authFailed
        /// Transport error or any other non-2xx (404 on builds without the RPC, 5xx, …).
        case unavailable
    }

    static let baseURLs = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]
    static let quotaSummaryPath = "/v1internal:retrieveUserQuotaSummary"
    static let fetchModelsPath = "/v1internal:fetchAvailableModels"
    static let loadCodeAssistPath = "/v1internal:loadCodeAssist"

    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    init(networkClient: any NetworkClient, timeout: TimeInterval = 15.0) {
        self.networkClient = networkClient
        self.timeout = timeout
    }

    /// POSTs a JSON body to `path` on each base URL in turn.
    func post(path: String, token: String, body: [String: String] = [:]) async -> Outcome {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)

        for base in Self.baseURLs {
            guard let url = URL(string: base + path) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await networkClient.request(request),
                  let http = response as? HTTPURLResponse else {
                AppLog.network.debug("Antigravity: \(base)\(path) unreachable")
                continue
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                AppLog.network.debug("Antigravity: \(path) rejected token (HTTP \(http.statusCode))")
                return .authFailed
            }
            if (200..<300).contains(http.statusCode) {
                return .ok(data)
            }
            AppLog.network.debug("Antigravity: \(base)\(path) returned HTTP \(http.statusCode)")
        }
        return .unavailable
    }
}
