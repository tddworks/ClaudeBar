import Foundation
import Domain

/// Carries a rule's action out: one POST to the URL that rule holds.
///
/// Infrastructure is the only place a `URLRequest` is built, so Domain never
/// holds a URL — the same fence `NotifyGatewayClient` keeps. The URL is a secret
/// and is read from the rule's repository at send time, never carried on the
/// body or written to a log.
///
/// It sends over `SameOriginRedirectClient`: a redirect that leaves the origin
/// the URL named is refused and its 3xx becomes the answer, so a token-carrying
/// URL is never re-sent to a host the person did not name (CANONICAL §5).
public struct WebhookClient: WebhookSending, Sendable {
    private let repository: any RuleRepository
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    public init(
        repository: any RuleRepository,
        networkClient: any NetworkClient = SameOriginRedirectClient.shared,
        timeout: TimeInterval = 15
    ) {
        self.repository = repository
        self.networkClient = networkClient
        self.timeout = timeout
    }

    public func send(_ body: WebhookBody, forRule ruleId: String) async throws {
        guard let string = repository.webhookURL(forRule: ruleId),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw WebhookError.noURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try body.encoded()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The URL carries a secret, and URLSession caches by the full URL, backed
        // by a file in ~/Library/Caches. A cached answer would write the secret to
        // disk in plaintext, outside the vault it is kept in.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let response: URLResponse
        do {
            (_, response) = try await networkClient.request(request)
        } catch {
            // The code and domain, never the description: every URL here carries a
            // secret, and a transport error's description is free to quote the URL
            // it failed on. The log file is plaintext and attached to bug reports.
            let failure = error as NSError
            AppLog.network.error("Rules: a webhook for rule \(ruleId) could not be reached (\(failure.domain) \(failure.code))")
            throw WebhookError.transportFailed(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            AppLog.network.error("Rules: a webhook for rule \(ruleId) answered something that was not an HTTP response")
            throw WebhookError.malformedResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            AppLog.network.error("Rules: a webhook for rule \(ruleId) answered HTTP \(http.statusCode)")
            throw WebhookError.refused(http.statusCode)
        }

        AppLog.network.debug("Rules: a webhook for rule \(ruleId) answered HTTP \(http.statusCode)")
    }
}

/// Why a webhook could not be sent. Each sentence can be shown in the pane and
/// none quotes the URL.
public enum WebhookError: Error, LocalizedError, Equatable {
    /// The rule has no URL yet, or the one it holds is not a usable http(s) URL.
    case noURL
    case transportFailed(String)
    case malformedResponse
    /// The endpoint answered with a status outside 2xx.
    case refused(Int)

    public var errorDescription: String? {
        switch self {
        case .noURL:
            "This rule has no webhook URL yet. Add one first."
        case .transportFailed(let reason):
            "Couldn't reach the webhook — \(reason)"
        case .malformedResponse:
            "The webhook answered something ClaudeBar could not read."
        case .refused(let status):
            "The webhook refused the request (HTTP \(status))."
        }
    }
}