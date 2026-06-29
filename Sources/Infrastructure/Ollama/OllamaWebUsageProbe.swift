import Foundation
import SweetCookieKit
import Domain

// MARK: - Ollama Web (Cookie-scrape) Probe

/// Probes the authenticated `ollama.com/settings` page using browser
/// session cookies imported via SweetCookieKit.
///
/// This is the fallback path for users who only log in to ollama.com via
/// the website and have not provisioned an API key. We grab the
/// `next-auth.session-token` (and chunked variants) for `ollama.com`,
/// fetch the rendered settings page, and pull session/weekly usage out of
/// the embedded HTML.
///
/// The implementation is intentionally permissive about parse failures —
/// Ollama's marketing page redesigns periodically, and if the markers go
/// missing we still surface a snapshot showing "logged in via session
/// cookie" so the user knows we found credentials.
public struct OllamaWebUsageProbe: UsageProbe {
    /// The set of cookie names recognised as session-auth cookies for
    /// ollama.com. The list mirrors the recognised set used by CodexBar.
    private static let recognisedCookieNames: Set<String> = [
        "session",
        "__Secure-session",
        "ollama_session",
        "__Host-ollama_session",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
    ]

    /// Domains we query for cookies.
    private static let cookieDomains = [
        "ollama.com",
        "www.ollama.com",
    ]

    /// The URL we GET to retrieve the rendered usage HTML.
    private static let settingsURL = URL(string: "https://ollama.com/settings")!

    private let cookieClient: BrowserCookieClient
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    /// Creates an Ollama Web probe.
    /// - Parameters:
    ///   - cookieClient: SweetCookieKit client (defaults to a fresh instance).
    ///   - networkClient: HTTP client (defaults to `URLSession.shared`).
    ///   - timeout: Request timeout in seconds.
    public init(
        cookieClient: BrowserCookieClient = BrowserCookieClient(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 30
    ) {
        self.cookieClient = cookieClient
        self.networkClient = networkClient
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        resolveCookieHeader() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard let cookieHeader = resolveCookieHeader() else {
            AppLog.probes.error("Ollama Web: no recognised session cookie found in any browser")
            throw ProbeError.authenticationRequired
        }

        AppLog.probes.info("Starting Ollama Web probe...")

        let html = try await fetchSettingsHTML(cookieHeader: cookieHeader)
        return Self.parseSettingsHTML(html, providerId: "ollama", now: Date())
    }

    // MARK: - Cookie Resolution

    /// Returns a `Cookie:` header string assembled from the first browser
    /// that contains a recognised ollama.com session cookie, or nil.
    private func resolveCookieHeader() -> String? {
        let query = BrowserCookieQuery(
            domains: Self.cookieDomains,
            domainMatch: .suffix,
            includeExpired: false
        )

        for browser in Browser.defaultImportOrder {
            do {
                let stores = try cookieClient.records(matching: query, in: browser)
                for store in stores {
                    let cookies = store.cookies(origin: query.origin)
                    let matched = cookies.filter { Self.isRecognisedCookie($0.name) }
                    guard !matched.isEmpty else { continue }
                    AppLog.probes.debug("Ollama Web: found session cookies in \(browser)")
                    return matched
                        .map { "\($0.name)=\($0.value)" }
                        .joined(separator: "; ")
                }
            } catch {
                continue
            }
        }
        AppLog.probes.debug("Ollama Web: no session cookies in any browser")
        return nil
    }

    /// Whether `name` looks like an ollama.com session cookie, including
    /// the next-auth chunked variants (`<name>.0`, `<name>.1`, ...).
    private static func isRecognisedCookie(_ name: String) -> Bool {
        if recognisedCookieNames.contains(name) { return true }
        return name.hasPrefix("__Secure-next-auth.session-token.")
            || name.hasPrefix("next-auth.session-token.")
    }

    // MARK: - HTTP

    private func fetchSettingsHTML(cookieHeader: String) async throws -> String {
        var request = URLRequest(url: Self.settingsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://ollama.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.settingsURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/537.36 (KHTML, like Gecko) "
                + "Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("Ollama Web: HTTP error - \(error.localizedDescription)")
            throw ProbeError.executionFailed("Ollama Web request failed: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid HTTP response from ollama.com")
        }

        AppLog.probes.debug("Ollama Web: status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return String(data: data, encoding: .utf8) ?? ""
        case 401, 403:
            throw ProbeError.sessionExpired(
                hint: "Re-authenticate at ollama.com in your browser."
            )
        default:
            throw ProbeError.executionFailed("ollama.com returned HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - HTML Parsing (static for testability)

    /// Parses the `ollama.com/settings` HTML into a `UsageSnapshot`.
    ///
    /// Pulls out plan name, account email, and the "Session usage" /
    /// "Weekly usage" percent + reset markers. If a section is missing it
    /// is simply omitted from the resulting snapshot — we never throw on
    /// partial data, because the marketing page changes shape often
    /// enough that we'd rather show something than nothing.
    public static func parseSettingsHTML(
        _ html: String,
        providerId: String,
        now: Date = Date()
    ) -> UsageSnapshot {
        let planName = parsePlanName(in: html)
        let email = parseAccountEmail(in: html)
        let session = parseUsageBlock(labels: ["Session usage", "Hourly usage"], in: html)
        let weekly = parseUsageBlock(labels: ["Weekly usage"], in: html)

        var quotas: [UsageQuota] = []
        if let session {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - session.usedPercent),
                quotaType: .session,
                providerId: providerId,
                resetsAt: session.resetsAt
            ))
        }
        if let weekly {
            quotas.append(UsageQuota(
                percentRemaining: max(0, 100 - weekly.usedPercent),
                quotaType: .weekly,
                providerId: providerId,
                resetsAt: weekly.resetsAt
            ))
        }

        let tier: AccountTier? = planName.flatMap {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .custom(trimmed.uppercased())
        }

        return UsageSnapshot(
            providerId: providerId,
            quotas: quotas,
            capturedAt: now,
            accountEmail: email,
            loginMethod: "Session cookie",
            accountTier: tier
        )
    }

    // MARK: - Parser Helpers

    private struct UsageBlock {
        let usedPercent: Double
        let resetsAt: Date?
    }

    private static func parsePlanName(in html: String) -> String? {
        let pattern = #"Cloud Usage\s*</span>\s*<span[^>]*>([^<]+)</span>"#
        return firstCapture(in: html, pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    private static func parseAccountEmail(in html: String) -> String? {
        let pattern = #"id=\"header-email\"[^>]*>([^<]+)<"#
        guard let raw = firstCapture(in: html, pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") ? trimmed : nil
    }

    private static func parseUsageBlock(labels: [String], in html: String) -> UsageBlock? {
        for label in labels {
            if let block = parseUsageBlock(label: label, in: html) {
                return block
            }
        }
        return nil
    }

    private static func parseUsageBlock(label: String, in html: String) -> UsageBlock? {
        guard let labelRange = html.range(of: label) else { return nil }
        let tail = String(html[labelRange.upperBound...])
        let window = String(tail.prefix(800))
        guard let usedPercent = parsePercent(in: window) else { return nil }
        return UsageBlock(usedPercent: usedPercent, resetsAt: parseISODate(in: window))
    }

    private static func parsePercent(in text: String) -> Double? {
        let usedPattern = #"([0-9]+(?:\.[0-9]+)?)\s*%\s*used"#
        if let raw = firstCapture(in: text, pattern: usedPattern, options: [.caseInsensitive]),
           let value = Double(raw) {
            return value
        }
        let widthPattern = #"width:\s*([0-9]+(?:\.[0-9]+)?)%"#
        if let raw = firstCapture(in: text, pattern: widthPattern, options: [.caseInsensitive]),
           let value = Double(raw) {
            return value
        }
        return nil
    }

    private static func parseISODate(in text: String) -> Date? {
        let pattern = #"data-time=\"([^\"]+)\""#
        guard let raw = firstCapture(in: text, pattern: pattern, options: []) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func firstCapture(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
