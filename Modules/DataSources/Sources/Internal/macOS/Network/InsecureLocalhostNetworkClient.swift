#if os(macOS)
import Foundation

/// Network client that accepts self-signed certificates for localhost connections.
/// This is required because Antigravity's local language server uses self-signed certs.
///
/// Note: This adapter is excluded from code coverage since it only wraps URLSession.
public struct InsecureLocalhostNetworkClient: NetworkClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 8.0) {
        let delegate = InsecureLocalhostDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, Self.isLoopback(url) else { throw URLError(.unsupportedURL) }
        return try await session.data(for: request)
    }

    static func isLoopback(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
            ["127.0.0.1", "localhost"].contains(url.host?.lowercased() ?? "")
    }

}

/// URLSession delegate that accepts self-signed certificates for localhost,
/// and follows a redirect only within the same local server — the loopback
/// pinning of the one same-origin rule (`SameOriginRedirectDelegate`).
final class InsecureLocalhostDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              InsecureLocalhostNetworkClient.isLoopback(target),
              SameOriginRedirectDelegate.sameOrigin(from: original, to: target) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only trust localhost connections
        let host = challenge.protectionSpace.host.lowercased()
        guard host == "127.0.0.1" || host == "localhost" else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Accept any certificate for localhost
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
#endif
