import Foundation
import Mockable
import Testing
@testable import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The client a local server is asked through: only this machine, and a
/// redirect followed only within the same server.
@Suite
struct LoopbackClientTests {
    final class Sent: @unchecked Sendable { var requests: [URLRequest] = [] }

    /// A client whose OS answers each address from `answers` (status,
    /// Location), and 200 for any other.
    private func client(_ answers: [String: (Int, String?)] = [:], sent: Sent = Sent()) -> LoopbackClient {
        let requests = MockLoopbackRequests()
        given(requests).send(.any).willProduce { request in
            sent.requests.append(request)
            let (status, location) = answers[request.url!.absoluteString] ?? (200, nil)
            let headers = location.map { ["Location": $0] } ?? [:]
            return (Data("from \(request.url!.absoluteString)".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }
        return LoopbackClient(requests: requests)
    }

    @Test(arguments: ["https://example.invalid/usage", "http://10.0.0.1:5001/usage", "https://127.0.0.2:5001/usage",
                      "ftp://127.0.0.1/usage"])
    func `should refuse an address off this machine before sending anything`(_ address: String) async {
        let sent = Sent()
        await #expect(throws: URLError.self) {
            try await client(sent: sent).request(URLRequest(url: URL(string: address)!))
        }
        #expect(sent.requests.isEmpty)
    }

    @Test(arguments: ["https://127.0.0.1:5001/status", "/status"])
    func `should follow a redirect within the same local server, keeping what was asked`(_ location: String) async throws {
        let sent = Sent()
        var request = URLRequest(url: URL(string: "https://127.0.0.1:5001/usage")!)
        request.httpMethod = "POST"
        request.setValue("tok", forHTTPHeaderField: "X-Csrf")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await client(["https://127.0.0.1:5001/usage": (307, location)], sent: sent).request(request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "from https://127.0.0.1:5001/status")
        let followed = try #require(sent.requests.last)
        #expect(followed.httpMethod == "POST")
        #expect(followed.value(forHTTPHeaderField: "X-Csrf") == "tok")
        #expect(followed.httpBody == Data("{}".utf8))
    }

    @Test func `should ask a 302 or 303 redirect's address with GET and no body`() async throws {
        let sent = Sent()
        var request = URLRequest(url: URL(string: "https://127.0.0.1:5001/usage")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)

        _ = try await client(["https://127.0.0.1:5001/usage": (303, "/status")], sent: sent).request(request)

        let followed = try #require(sent.requests.last)
        #expect(followed.httpMethod == "GET")
        #expect(followed.httpBody == nil)
    }

    @Test(arguments: ["https://example.invalid/status", "https://127.0.0.1:5002/status", "http://127.0.0.1:5001/status",
                      "https://localhost:5001/status"])
    func `should hand back a redirect that leaves the local server, unfollowed`(_ location: String) async throws {
        let sent = Sent()
        let (_, response) = try await client(["https://127.0.0.1:5001/usage": (302, location)], sent: sent)
            .request(URLRequest(url: URL(string: "https://127.0.0.1:5001/usage")!))
        #expect((response as? HTTPURLResponse)?.statusCode == 302)
        #expect(sent.requests.count == 1)
    }

    @Test func `should stop following a server that keeps redirecting`() async throws {
        let sent = Sent()
        let loop = ["https://127.0.0.1:5001/a": (302, "/b"), "https://127.0.0.1:5001/b": (302, "/a")]
        let (_, response) = try await client(loop.mapValues { ($0.0, Optional($0.1)) }, sent: sent)
            .request(URLRequest(url: URL(string: "https://127.0.0.1:5001/a")!))
        #expect((response as? HTTPURLResponse)?.statusCode == 302)
        #expect(sent.requests.count == LoopbackClient.redirectLimit + 1)
    }
}
