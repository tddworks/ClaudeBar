import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The network's one law: **a fetch keeps to the origin it named**
/// ([CANONICAL_MODEL §5](../../../../../docs/architecture/CANONICAL_MODEL.md)).
/// A redirect that leaves it — another host, port or scheme — is refused, so
/// an `Authorization` header or a token-carving URL is never re-sent to a
/// server the fetch didn't name, key or no key. Refusing (not erroring)
/// hands the 3xx back, and the fetcher words it as any other status.
final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              Self.sameOrigin(from: original, to: target) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    /// Same scheme, host and port — with a port left implicit read as the
    /// scheme's default, so a redirect that merely restates `:443` follows.
    static func sameOrigin(from: URL, to: URL) -> Bool {
        from.scheme?.lowercased() == to.scheme?.lowercased()
            && from.host?.lowercased() == to.host?.lowercased()
            && effectivePort(from) == effectivePort(to)
    }

    private static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "https" ? 443 : 80
    }
}

/// The remote network every fetch shares: one `URLSession`, built once, whose
/// redirects never leave the origin (the law above). Local-server fetches
/// keep their own client (`LoopbackClient`), which follows a redirect by
/// this same `sameOrigin`, pinned to this machine.
///
/// Public, so a client outside `DataSources` — the Rules webhook's POST —
/// sends under the same law rather than following a redirect off the origin
/// with a URL that carries a token.
public struct SameOriginRedirectClient: NetworkClient {
    /// Shared, like the `URLSession.shared` it replaced: a session holds its
    /// delegate strongly, and a fetch is made per login and per test, so a
    /// client built on each `make` would only pile sessions up.
    public static let shared = SameOriginRedirectClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration, delegate: SameOriginRedirectDelegate(), delegateQueue: nil)
    }

    /// Sends the request, refusing any redirect that leaves the origin it named.
    public func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
