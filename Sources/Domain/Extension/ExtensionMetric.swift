import Foundation

/// A generic metric value displayed by extension sections.
/// Used for custom data that doesn't fit the standard quota/cost/daily models.
public struct ExtensionMetric: Sendable, Equatable, Codable {
    public let label: String
    public let value: String
    public let unit: String
    public let icon: String?
    public let color: String?
    public let delta: MetricDelta?
    public let progress: Double?

    /// Section this metric belongs to when produced by an aggregating
    /// provider (e.g. Oh My Pi account rows). nil for extension-script
    /// metrics, which render in the flat metrics grid. Optional and absent
    /// from older payloads, so extension JSON stays backward compatible.
    public let group: String?

    public init(
        label: String,
        value: String,
        unit: String,
        icon: String? = nil,
        color: String? = nil,
        delta: MetricDelta? = nil,
        progress: Double? = nil,
        group: String? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.icon = icon
        self.color = color
        self.delta = delta
        self.progress = progress
        self.group = group
    }
}

/// Comparison delta for a metric (e.g., "Vs Mar 16 -$701.58 (98.6%)")
public struct MetricDelta: Sendable, Equatable, Codable {
    public let vs: String
    public let value: String
    public let percent: Double?

    public init(vs: String, value: String, percent: Double? = nil) {
        self.vs = vs
        self.value = value
        self.percent = percent
    }
}

/// Status information for a status banner section.
public struct StatusInfo: Sendable, Equatable, Codable {
    public let text: String
    public let level: StatusLevel

    public init(text: String, level: StatusLevel) {
        self.text = text
        self.level = level
    }
}

/// Severity level for status banners.
public enum StatusLevel: String, Sendable, Equatable, Codable {
    case healthy
    case warning
    case critical
    case inactive
}
