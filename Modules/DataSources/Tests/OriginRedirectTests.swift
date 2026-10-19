import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import DataSources

/// The law: a credential travels only to the origin its fetch names.
/// A redirect that leaves it is not followed, so Authorization headers and
/// token URLs are never re-sent to a server the fetch didn't name.
@Suite struct OriginRedirectTests {
    private let session = URLSession(configuration: .ephemeral)

    private func redirect(from origin: String, to destination: String, follow: @escaping (URLRequest?) -> Void) {
        let task = session.dataTask(with: URL(string: origin)!)
        let response = HTTPURLResponse(url: URL(string: origin)!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        SameOriginRedirectDelegate().urlSession(session, task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: destination)!), completionHandler: follow)
    }

    @Test func `should follow a redirect that stays on the origin`() {
        var followed: URLRequest?
        redirect(from: "https://api.example.com/usage", to: "https://api.example.com/v2/usage") { followed = $0 }
        #expect(followed?.url?.absoluteString == "https://api.example.com/v2/usage")
    }

    @Test func `should follow a redirect that only restates the default port`() {
        var followed: URLRequest?
        redirect(from: "https://api.example.com/usage", to: "https://api.example.com:443/v2/usage") { followed = $0 }
        #expect(followed != nil)
    }

    @Test(arguments: [
        "https://evil.example.net/collect",           // another host
        "http://api.example.com/usage",               // a downgrade to plain HTTP
        "https://api.example.com:8443/usage",         // another port
    ])
    func `should refuse a redirect that leaves the origin`(_ destination: String) {
        var handled = false
        var followed: URLRequest?
        redirect(from: "https://api.example.com/usage", to: destination) {
            handled = true
            followed = $0
        }
        #expect(handled)
        #expect(followed == nil)
    }
}
