import Foundation

/// *WHERE THE WORK WENT* — each project summed over a range, largest first
/// in a unit, each with its share. The unnamed part is a part too, so the
/// parts add up to the range as a day's project lines add up to the day.
/// Built from `Days` (CANONICAL §5, `ByProject`).
public struct ByProject: Sendable, Equatable {
    /// One project's part of the range.
    public struct Part: Sendable, Equatable {
        /// The project's lines over the range, added up.
        public let line: ProjectUsageLine
        /// The line's value in the read's unit.
        public let value: Double
        /// The line's part of the range, 0…1 — 0 when the range holds nothing.
        public let share: Double
    }

    /// Every project the range names, the unnamed part among them; largest
    /// first, projects that tie in name order.
    public let parts: [Part]

    /// The project used most, or nil when the range names none. The unnamed
    /// part is a part, never a project, so it is never the top one.
    public var top: Part? { parts.first { !$0.line.project.isEmpty && $0.value > 0 } }

    /// `range`'s project lines summed per project and read in `unit`.
    public init(of range: Days, in unit: Days.Unit) {
        var sums: [String: ProjectUsageLine] = [:]
        for line in range.stats.flatMap(\.projects) {
            sums[line.project] = sums[line.project].map { $0 + line } ?? line
        }
        let values = sums.values.map { (line: $0, value: range.value(of: $0, in: unit)) }
        let whole = values.reduce(0) { $0 + $1.value }
        parts = values
            .map { Part(line: $0.line, value: $0.value, share: whole > 0 ? $0.value / whole : 0) }
            .sorted { $0.value == $1.value ? $0.line.project < $1.line.project : $0.value > $1.value }
    }
}
