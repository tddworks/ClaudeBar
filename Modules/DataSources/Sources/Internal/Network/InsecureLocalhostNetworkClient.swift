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
        try await session.data(for: request)
    }
}

/// URLSession delegate that accepts self-signed certificates for localhost.
private final class InsecureLocalhostDelegate: NSObject, URLSessionDelegate {
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
