import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// One POST per send: a 2xx is sent, anything else failed with its code.
@Suite
struct WebhookClientTests {
    private let address = try! WebhookAddress("https://hooks.slack.com/services/T000/B000/XXXX")
    private let body = Data(#"{"text":"hi"}"#.utf8)

    private func answering(_ status: Int) -> MockNetworkClient {
        let network = MockNetworkClient()
        given(network).request(.any).willReturn((Data(), HTTPURLResponse(
            url: address.url, statusCode: status, httpVersion: nil, headerFields: nil)!))
        return network
    }

    private func failing(_ code: Int) -> MockNetworkClient {
        let network = MockNetworkClient()
        given(network).request(.any).willThrow(NSError(domain: NSURLErrorDomain, code: code))
        return network
    }

    @Test func `should POST the body to the webhook's URL as JSON, never from a cache`() async {
        final class Seen: @unchecked Sendable { var request: URLRequest? }
        let seen = Seen()
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            seen.request = request
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        _ = await WebhookClient(networkClient: network).post(body, to: address, webhook: "id1")

        #expect(seen.request?.url == address.url)
        #expect(seen.request?.httpMethod == "POST")
        #expect(seen.request?.httpBody == body)
        #expect(seen.request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(seen.request?.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(seen.request?.timeoutInterval == 10)
    }

    @Test func `should call a 2xx sent`() async {
        #expect(await WebhookClient(networkClient: answering(204)).post(body, to: address, webhook: "id1") == .sent)
    }

    @Test func `should fail with the code a webhook answered`() async {
        #expect(await WebhookClient(networkClient: answering(404)).post(body, to: address, webhook: "id1")
            == .failed(.status(404)))
    }

    @Test func `should fail as redirected away when the URL sends it to another origin`() async {
        #expect(await WebhookClient(networkClient: answering(302)).post(body, to: address, webhook: "id1")
            == .failed(.redirectedAway))
    }

    @Test func `should fail as timed out when no answer comes in time`() async {
        #expect(await WebhookClient(networkClient: failing(NSURLErrorTimedOut)).post(body, to: address, webhook: "id1")
            == .failed(.timedOut))
    }

    @Test func `should fail as unreachable when the host can't be reached`() async {
        #expect(await WebhookClient(networkClient: failing(NSURLErrorCannotFindHost)).post(body, to: address, webhook: "id1")
            == .failed(.unreachable))
    }
}
