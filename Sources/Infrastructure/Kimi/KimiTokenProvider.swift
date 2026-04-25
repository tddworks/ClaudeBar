import Foundation
import Domain

/// Protocol for resolving Kimi authentication tokens.
/// Enables testability by allowing mock implementations.
public protocol KimiTokenProviding: Sendable {
    func resolveToken() throws -> String
}

/// Resolves Kimi authentication token from environment variable or browser cookies.
///
/// Resolution order:
/// 1. `KIMI_AUTH_TOKEN` environment variable
/// 2. `kimi-auth` cookie from browser cookie stores (macOS 13+ via SweetCookieKit)
public struct KimiCookieTokenProvider: KimiTokenProviding {
    public init() {}

    public func resolveToken() throws -> String {
        // 1. Check environment variable
        if let envToken = ProcessInfo.processInfo.environment["KIMI_AUTH_TOKEN"],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            AppLog.probes.debug("Kimi: Using token from KIMI_AUTH_TOKEN env var")
            return envToken
        }

        // 2. Try extracting from browser cookies (macOS 13+ only)
        if let browserToken = fetchFromBrowser() {
            AppLog.probes.debug("Kimi: Using token from browser cookie")
            return browserToken
        }

        AppLog.probes.error("Kimi: No authentication token found")
        throw ProbeError.authenticationRequired
    }

    private func fetchFromBrowser() -> String? {
        #if canImport(SweetCookieKit)
        if #available(macOS 13, *) {
            return _KimiBrowserCookieFetcher().fetchCookie()
        }
        #endif
        return nil
    }
}
