import Foundation
import Mockable
import SweetCookieKit

/// One cookie from a browser store. Its value never enters a log.
public struct BrowserCookie: Sendable, Equatable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// The browsers' cookie stores — the port `browserCookies` reads through.
@Mockable
public protocol BrowserCookieReading: Sendable {
    /// The cookies with these names for these domains (suffix match), one
    /// list per store that has any, in the browsers' import order.
    func stores(domains: [String], names: [String]) -> [[BrowserCookie]]
}

/// The real stores, read with SweetCookieKit.
public struct SystemBrowserCookies: BrowserCookieReading {
    public init() {}

    public func stores(domains: [String], names: [String]) -> [[BrowserCookie]] {
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: domains, domainMatch: .suffix, includeExpired: false)
        var found: [[BrowserCookie]] = []
        for browser in Browser.defaultImportOrder {
            guard let stores = try? client.records(matching: query, in: browser) else { continue }
            for store in stores {
                let cookies = store.cookies(origin: query.origin)
                    .filter { names.contains($0.name) }
                    .map { BrowserCookie(name: $0.name, value: $0.value) }
                if !cookies.isEmpty { found.append(cookies) }
            }
        }
        return found
    }
}

/// `browserCookies` — the first store holding a named, non-empty cookie answers.
struct BrowserCookieReader: CredentialFinding {
    let query: BrowserCookieCredential
    let cookies: any BrowserCookieReading

    func find() throws -> FoundCredential? {
        for store in cookies.stores(domains: query.domains, names: query.names) {
            let present = store.filter { query.names.contains($0.name) && !$0.value.isEmpty }
            guard let first = present.first else { continue }
            let token = switch query.format {
            case .value: first.value
            case .header: present.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
            return FoundCredential(credential: Credential(["token": token]), save: nil)
        }
        return nil
    }
}
