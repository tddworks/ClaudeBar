import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The client a local server is asked through, the same on every platform:
/// an address off this machine is refused before anything is sent, and a
/// redirect is followed only within the same origin (the network's one law,
/// `SameOriginRedirectDelegate.sameOrigin`). A redirect anywhere else is the
/// answer, unfollowed. The OS only sends one request, trusting the
/// certificate the server presents, and refuses a host off this machine
/// itself (`isLoopback`, the one rule both read).
struct LoopbackClient: NetworkClient {
    /// How many redirects one request follows before the last is its answer.
    static let redirectLimit = 5

    let requests: any LoopbackRequests

    func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url, Self.isLoopback(url) else { throw URLError(.unsupportedURL) }
        var current = request
        var answer = try await requests.send(current)
        for _ in 0..<Self.redirectLimit {
            guard let next = Self.redirect(from: current, answered: answer.1) else { break }
            current = next
            answer = try await requests.send(current)
        }
        return answer
    }

    /// Whether `url` asks a server on this machine over HTTP or HTTPS.
    static func isLoopback(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && isLoopback(host: url.host ?? "")
    }

    /// Whether `host` names this machine: 127.0.0.1 or localhost.
    static func isLoopback(host: String) -> Bool {
        ["127.0.0.1", "localhost"].contains(host.lowercased())
    }

    /// The request a redirect asks for, when it stays on the same origin.
    /// A 307 or 308 keeps the method and body; any other asks with `GET`.
    private static func redirect(from request: URLRequest, answered response: HTTPURLResponse) -> URLRequest? {
        guard (300..<400).contains(response.statusCode), let original = request.url,
              let location = response.value(forHTTPHeaderField: "Location"),
              let target = URL(string: location, relativeTo: original)?.absoluteURL,
              SameOriginRedirectDelegate.sameOrigin(from: original, to: target) else { return nil }
        var next = request
        next.url = target
        if ![307, 308].contains(response.statusCode) {
            next.httpMethod = "GET"
            next.httpBody = nil
        }
        return next
    }
}
