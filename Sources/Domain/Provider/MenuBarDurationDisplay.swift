import Foundation

/// Formatted reset-duration value for the menu bar duration label.
/// Sibling to `MenuBarPercentageDisplay`; both display types are driven by the
/// same underlying `UsageQuota` but render different facets.
public struct MenuBarDurationDisplay: Sendable, Equatable {
    public let status: QuotaStatus
    public let quota: UsageQuota

    /// Computed (not stored) so the countdown reflects the current wall clock
    /// every time SwiftUI evaluates the menu bar label, instead of freezing at
    /// the value captured when this display was constructed.
    public var text: String {
        quota.compactResetTime
            ?? Self.compactResetText(quota.resetText)
            ?? "—"
    }

    public init(
        quota: UsageQuota,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) {
        self.quota = quota
        self.status = burnRateWarningEnabled
            ? quota.paceAwareStatus(burnRateThreshold: burnRateThreshold)
            : quota.status
    }

    private static func compactResetText(_ resetText: String?) -> String? {
        guard let resetText else { return nil }
        let lower = resetText.lowercased()
        guard lower.contains("reset") else { return nil }

        let pattern = #"(\d+)\s*([dhm])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(resetText.startIndex..<resetText.endIndex, in: resetText)
        let matches = regex.matches(in: resetText, options: [], range: range)
        let parts = matches.compactMap { match -> String? in
            guard match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 1), in: resetText),
                  let unitRange = Range(match.range(at: 2), in: resetText) else {
                return nil
            }
            return "\(resetText[valueRange])\(resetText[unitRange].lowercased())"
        }

        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " ")
    }
}
