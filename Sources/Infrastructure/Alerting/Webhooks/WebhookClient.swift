import Foundation
import Domain

/// One POST of a webhook's body to its URL.
///
/// It sends over `SameOriginRedirectClient`: a redirect that leaves the URL's
/// origin is refused and its 3xx becomes the answer, so a URL carrying a token
/// is never re-sent to a host the person didn't name. One attempt, no retry.
///
/// The URL is a secret, so nothing that could carry it reaches a log or the
/// pane: the log names the webhook's id and a code, never the URL or an
/// error's description, which is free to quote it.
public struct WebhookClient: WebhookSending, Sendable {
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    public init(networkClient: any NetworkClient = SameOriginRedirectClient.shared, timeout: TimeInterval = 10) {
        self.networkClient = networkClient
        self.timeout = timeout
    }

    public func post(_ body: Data, to address: WebhookAddress, webhook id: String) async -> WebhookPost {
        var request = URLRequest(url: address.url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // URLSession caches by the full URL, in a file under ~/Library/Caches:
        // a cached answer would write the secret to disk.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let response: URLResponse
        do {
            (_, response) = try await networkClient.request(request)
        } catch {
            let failure = Self.failure(error)
            AppLog.network.error("Webhook \(id) failed: \(Self.code(failure)) (\((error as NSError).domain) \((error as NSError).code))")
            return .failed(failure)
        }
        guard let http = response as? HTTPURLResponse else {
            AppLog.network.error("Webhook \(id) failed: the answer was not HTTP")
            return .failed(.unreachable)
        }
        switch http.statusCode {
        case 200..<300:
            AppLog.network.info("Webhook \(id) sent: HTTP \(http.statusCode)")
            return .sent
        case 300..<400:
            AppLog.network.error("Webhook \(id) failed: redirected to another origin (HTTP \(http.statusCode))")
            return .failed(.redirectedAway)
        default:
            AppLog.network.error("Webhook \(id) failed: HTTP \(http.statusCode)")
            return .failed(.status(http.statusCode))
        }
    }

    /// A transport error, as a code the pane can print.
    static func failure(_ error: Error) -> WebhookFailure {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .unreachable }
        return error.code == NSURLErrorTimedOut ? .timedOut : .unreachable
    }

    private static func code(_ failure: WebhookFailure) -> String {
        switch failure {
        case .status(let code): "HTTP \(code)"
        case .timedOut: "timed out"
        case .unreachable: "unreachable"
        case .redirectedAway: "redirected away"
        case .noURL: "no URL"
        }
    }
}
