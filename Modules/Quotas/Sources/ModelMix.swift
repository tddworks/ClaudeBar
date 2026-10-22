import Foundation

/// *Which models do I lean on* — each model summed over a range, largest first
/// in a unit, each with its share. The unnamed line is a part too, so the
/// parts add up to the range as a day's lines add up to the day. Built from
/// `Days` (CANONICAL §5, `ModelMix`).
public struct ModelMix: Sendable, Equatable {
    /// One model's part of the range.
    public struct Part: Sendable, Equatable {
        /// The model's lines over the range, added up.
        public let line: ModelUsageLine
        /// The line's value in the mix's unit.
        public let value: Double
        /// The line's part of the range, 0…1 — 0 when the range holds nothing.
        public let share: Double
    }

    /// Every model the range names, the unnamed line among them; largest
    /// first, models that tie in name order.
    public let parts: [Part]

    /// The model leaned on most, or nil when the range names none.
    public var top: Part? { parts.first }

    /// `range`'s lines summed per model and read in `unit`.
    public init(of range: Days, in unit: Days.Unit) {
        var sums: [String: ModelUsageLine] = [:]
        for line in range.stats.flatMap(\.lines) {
            sums[line.model] = sums[line.model].map { $0 + line } ?? line
        }
        let values = sums.values.map { (line: $0, value: range.value(of: $0, in: unit)) }
        let whole = values.reduce(0) { $0 + $1.value }
        parts = values
            .map { Part(line: $0.line, value: $0.value, share: whole > 0 ? $0.value / whole : 0) }
            .sorted { $0.value == $1.value ? $0.line.model < $1.line.model : $0.value > $1.value }
    }
}
