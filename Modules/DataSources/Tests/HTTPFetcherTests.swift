import Quotas
import Foundation
import Mockable
import Testing
@testable import DataSources

@Suite
struct HTTPFetcherTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Retry-After

    @Test
    func `Retry-After accepts positive seconds`() {
        #expect(HTTPFetcher.retryAfter("120", now: Self.now) == 120)
        #expect(HTTPFetcher.retryAfter("1", now: Self.now) == 1)
    }

    @Test
    func `Retry-After rejects zero seconds`() {
        // /api/oauth/usage has been observed returning Retry-After: 0 while
        // still 429ing (anthropics/claude-code#30930). Treat 0 as no usable
        // value so the caller applies its fallback window instead.
        #expect(HTTPFetcher.retryAfter("0", now: Self.now) == nil)
    }

    @Test
    func `Retry-After accepts an HTTP-date in the future`() {
        // 2023-11-14 22:13:20 UTC + 60s = 2023-11-14 22:14:20 UTC
        #expect(HTTPFetcher.retryAfter("Tue, 14 Nov 2023 22:14:20 GMT", now: Self.now) == 60)
    }

    @Test
    func `Retry-After rejects an HTTP-date in the past`() {
        #expect(HTTPFetcher.retryAfter("Tue, 14 Nov 2023 22:00:00 GMT", now: Self.now) == nil)
    }

    @Test
    func `Retry-After rejects malformed and empty values`() {
        #expect(HTTPFetcher.retryAfter(nil, now: Self.now) == nil)
        #expect(HTTPFetcher.retryAfter("", now: Self.now) == nil)
        #expect(HTTPFetcher.retryAfter("   ", now: Self.now) == nil)
        #expect(HTTPFetcher.retryAfter("not a number", now: Self.now) == nil)
        #expect(HTTPFetcher.retryAfter("-5", now: Self.now) == nil)
    }

    // MARK: - 429

    private func fetch429(_ headers: [String: String]) async -> Error? {
        let network = MockNetworkClient()
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil, headerFields: headers)!
        given(network).request(.any).willReturn((Data(), response))
        let fetcher = HTTPFetcher(request: HTTPRequest(url: "https://example.com"), network: network, now: { Self.now })
        do {
            _ = try await fetcher.fetch(with: nil)
            return nil
        } catch {
            return error
        }
    }

    @Test
    func `a 429 is rate limited for as long as Retry-After says`() async {
        let error = await fetch429(["Retry-After": "120"]) as? HTTPStatusError

        #expect(error?.status == 429)
        #expect(error?.reason == .rateLimited(retryAt: Self.now.addingTimeInterval(120)))
    }

    @Test
    func `a 429 without a usable Retry-After waits five minutes`() async {
        let missing = await fetch429([:]) as? HTTPStatusError
        let zero = await fetch429(["Retry-After": "0"]) as? HTTPStatusError

        #expect(missing?.reason == .rateLimited(retryAt: Self.now.addingTimeInterval(300)))
        #expect(zero?.reason == .rateLimited(retryAt: Self.now.addingTimeInterval(300)))
    }

    // MARK: - Filling a URL

    @Test
    func `a value filled into a URL is percent-encoded`() async throws {
        let network = MockNetworkClient()
        let seen = URLBox()
        given(network).request(.any).willProduce { request in
            seen.url = request.url
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let fetcher = HTTPFetcher(request: HTTPRequest(url: "https://acme.test/usage?org={{org}}"), network: network, now: { Self.now })

        _ = try await fetcher.fetch(with: Credential(["org": "team & org"]))

        let items = URLComponents(url: try #require(seen.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(items == [URLQueryItem(name: "org", value: "team & org")])
    }
}

private final class URLBox: @unchecked Sendable {
    var url: URL?
}
