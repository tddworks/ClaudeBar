import Foundation
import Domain

/// Pure add/normalize rules behind the alert-threshold editor in Settings
/// (issue #68). Kept out of the view so the rules are unit-testable and the
/// pane only wires them to `AppSettings.alertThresholds`.
enum AlertThresholdList {
    /// Room for a sane spread (e.g. 90/75/60/45/30/15) without an unbounded list.
    static let maxCount = 8

    /// Parses one user-entered percentage and returns the updated list, or nil
    /// when the input should not change anything: non-numeric, a duplicate of
    /// an existing threshold, or added to a full list. Values are clamped into
    /// 0...100 by `QuotaAlertThreshold`'s own normalization.
    static func adding(_ raw: String, to current: [Double]) -> [Double]? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
        guard let value = Double(trimmed) else { return nil }
        let threshold = QuotaAlertThreshold(percent: value)

        guard current.count < maxCount else { return nil }
        guard !current.contains(where: { $0 == threshold.percent }) else { return nil }

        return current + [threshold.percent]
    }
}
