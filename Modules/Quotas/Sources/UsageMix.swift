import Foundation

/// A RANGE SPLIT BY SOMETHING — each line summed over the range, largest
/// first in a unit, each with its share. The unnamed part is a part too, so
/// the parts add up to the range as a day's lines add up to the day. Built
/// from `Days`; *which models do I lean on* is `ModelMix`, *where did the
/// work go* is `ByProject` (CANONICAL §5, `UsageMix`).
public struct UsageMix<Line: UsageLine>: Sendable, Equatable {
    /// One line's part of the range.
    public struct Part: Sendable, Equatable {
        /// The line over the range, added up.
        public let line: Line
        /// The line's value in the mix's unit.
        public let value: Double
        /// The line's part of the range, 0…1 — 0 when the range holds nothing.
        public let share: Double
    }

    /// Every line the range holds, the unnamed part among them; largest
    /// first, lines that tie in name order.
    public let parts: [Part]

    /// The line used most, or nil when the range names none. The unnamed
    /// part is a part, never a name, so it is never the top one.
    public var top: Part? { parts.first { !$0.line.name.isEmpty && $0.value > 0 } }

    /// The names the range holds, in name order — a name keeps its colour
    /// from view to view. The unnamed part is not a name.
    public var names: [String] { parts.map(\.line.name).filter { !$0.isEmpty }.sorted() }

    /// Whether the range names nothing — no split to offer.
    public var isEmpty: Bool { names.isEmpty }

    /// `range`'s days split (`Line.split(of:)`), summed per name and read in `unit`.
    public init(of range: Days, in unit: Days.Unit) {
        let lines = Line.summed(range.stats.flatMap(Line.split(of:)))
        let values = lines.map { (line: $0, value: $0.spend.value(in: unit)) }
        let whole = values.reduce(0) { $0 + $1.value }
        parts = values
            .map { Part(line: $0.line, value: $0.value, share: whole > 0 ? $0.value / whole : 0) }
            .sorted { $0.value == $1.value ? $0.line.name < $1.line.name : $0.value > $1.value }
    }
}

/// *Which models do I lean on* — the range split by model.
public typealias ModelMix = UsageMix<ModelUsageLine>

/// *Where the work went* — the range split by project.
public typealias ByProject = UsageMix<ProjectUsageLine>
