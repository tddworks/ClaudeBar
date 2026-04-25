import Foundation
#if canImport(SweetCookieKit)
import SweetCookieKit
#endif

#if canImport(SweetCookieKit)
@available(macOS 13, *)
struct _KimiBrowserCookieFetcher {
    func fetchCookie() -> String? {
        let cookieClient = BrowserCookieClient()
        let query = BrowserCookieQuery(
            domains: ["www.kimi.com", "kimi.com"],
            domainMatch: .suffix,
            includeExpired: false
        )

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    if let auth = cookies.first(where: { $0.name == "kimi-auth" }),
                       !auth.value.isEmpty
                    {
                        return auth.value
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}
#endif
