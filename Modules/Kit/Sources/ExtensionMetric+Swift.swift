import Foundation
import ClaudeBarKit

extension ExtensionMetric {
    public convenience init(
        label: String,
        value: String,
        unit: String,
        icon: String? = nil,
        color: String? = nil,
        delta: MetricDelta? = nil,
        progress: Double? = nil,
        group: String? = nil
    ) {
        self.init(
            label: label, value: value, unit: unit, icon: icon, color: color, delta: delta,
            progressOrNull: progress.kotlin, group: group
        )
    }

    public static func == (lhs: ExtensionMetric, rhs: ExtensionMetric) -> Bool { lhs.isEqual(rhs) }

    public var progress: Double? { progressOrNull.swift }
}

extension MetricDelta {
    public convenience init(vs: String, value: String, percent: Double? = nil) {
        self.init(vs: vs, value: value, percentOrNull: percent.kotlin)
    }

    public static func == (lhs: MetricDelta, rhs: MetricDelta) -> Bool { lhs.isEqual(rhs) }

    public var percent: Double? { percentOrNull.swift }
}

// An extension reports metrics as JSON. A Kotlin class can't adopt Codable from Swift,
// so a reported metric is read through `Reported`, with the keys extensions write.
extension ExtensionMetric {
    public struct Reported: Codable, Sendable {
        let label: String
        let value: String
        let unit: String
        let icon: String?
        let color: String?
        let delta: MetricDelta.Reported?
        let progress: Double?
        let group: String?

        public var metric: ExtensionMetric {
            ExtensionMetric(
                label: label, value: value, unit: unit, icon: icon, color: color,
                delta: delta?.delta, progress: progress, group: group
            )
        }
    }
}

extension MetricDelta {
    public struct Reported: Codable, Sendable {
        let vs: String
        let value: String
        let percent: Double?

        public var delta: MetricDelta { MetricDelta(vs: vs, value: value, percent: percent) }
    }
}
