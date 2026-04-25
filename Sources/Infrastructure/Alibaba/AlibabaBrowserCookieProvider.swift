import Foundation
import Domain

/// Resolves Alibaba Cloud authentication cookies from browser cookie stores.
///
/// On macOS 13+, uses SweetCookieKit for automatic browser cookie extraction.
/// On macOS 12, returns nil (manual cookie entry via settings still works).
public struct AlibabaBrowserCookieProvider: AlibabaCookieProviding {
    public init() {}

    public func extractBrowserCookies() -> String? {
        #if canImport(SweetCookieKit)
        if #available(macOS 13, *) {
            return _AlibabaBrowserCookieProvider().extractBrowserCookies()
        }
        #endif
        return nil
    }
}
