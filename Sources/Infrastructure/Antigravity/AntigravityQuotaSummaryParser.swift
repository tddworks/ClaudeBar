import Foundation
import Domain

/// Parses the `RetrieveUserQuotaSummary` / `v1internal:retrieveUserQuotaSummary` payload —
/// the only Antigravity endpoint that reports the two shared pools (Gemini, and every
/// non-Gemini model such as Claude) with both their rolling 5-hour and weekly windows.
///
/// Accepts both the language server envelope (`{"response": {"groups": …}}`) and the bare
/// Cloud Code payload (`{"groups": …}`).
enum AntigravityQuotaSummaryParser {

    private static let geminiGroup = "Gemini"
    private static let claudeGroup = "Claude & others"

    /// Known buckets, matched by exact `bucketId` only, in display order.
    ///
    /// `menuBarTitle` is the prefix shown in the dual-window menu bar label
    /// (e.g. "Gemini 80%" or "Claude Weekly 20%"). It is kept separate from
    /// `compactTitle`, which is used inside the popover quota card header.
    private static let buckets: [(id: String, quotaType: QuotaType, group: String, compactTitle: String, menuBarTitle: String)] = [
        ("gemini-5h",    .session,                   geminiGroup,  "5h", "Gemini"),
        ("gemini-weekly",.weekly,                    geminiGroup,  "7d", "Gemini Weekly"),
        ("3p-5h",        .modelSpecific("Claude"),   claudeGroup,  "5h", "Claude"),
        ("3p-weekly",    .modelSpecific("Claude Weekly"), claudeGroup, "7d", "Claude Weekly")
    ]

    /// Returns nil when the payload is not a quota summary at all (caller may fall back to
    /// the legacy per-model endpoints). A non-nil result — even an empty one — is authoritative.
    /// Buckets without a usable `remainingFraction` are dropped rather than reported as 0%.
    static func parse(_ data: Data, providerId: String) -> [UsageQuota]? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let groups = envelope.response?.groups ?? envelope.groups else {
            return nil
        }

        var byID: [String: Bucket] = [:]
        for bucket in groups.flatMap({ $0.buckets ?? [] }) {
            guard let id = bucket.bucketId, byID[id] == nil else { continue }
            byID[id] = bucket
        }

        return buckets.compactMap { spec in
            guard let bucket = byID[spec.id] else { return nil }
            guard let fraction = bucket.remainingFraction, fraction.isFinite else {
                AppLog.probes.warning("Antigravity: quota bucket '\(spec.id)' has no remainingFraction; skipping")
                return nil
            }
            return UsageQuota(
                percentRemaining: fraction * 100,
                quotaType: spec.quotaType,
                providerId: providerId,
                resetsAt: bucket.resetTime.flatMap(parseDate),
                group: spec.group,
                compactTitle: spec.compactTitle,
                menuBarTitle: spec.menuBarTitle
            )
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        if let seconds = Double(value) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    // MARK: - Wire format

    private struct Envelope: Decodable {
        let response: Root?
        let groups: [Group]?
    }

    private struct Root: Decodable {
        let groups: [Group]?
    }

    private struct Group: Decodable {
        let buckets: [Bucket]?
    }

    /// Lenient: a malformed bucket decodes to nil fields instead of failing the whole summary.
    private struct Bucket: Decodable {
        let bucketId: String?
        let remainingFraction: Double?
        let resetTime: String?

        private enum CodingKeys: String, CodingKey { case bucketId, remainingFraction, resetTime }

        init(from decoder: Decoder) {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            bucketId = container.flatMap { try? $0.decodeIfPresent(String.self, forKey: .bucketId) }
            remainingFraction = container.flatMap { try? $0.decodeIfPresent(Double.self, forKey: .remainingFraction) }
            resetTime = container.flatMap { try? $0.decodeIfPresent(String.self, forKey: .resetTime) }
        }
    }
}
