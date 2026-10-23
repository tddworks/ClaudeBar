import Foundation

/// *What did all of it add up to?* — one range across every provider, against
/// the range before it. Built from each provider's `Days`, keyed by provider
/// id; the top model is `ModelMix`'s and the biggest day `DayActivity`'s, read
/// over every provider's days at once. A read, never stored; the one read that
/// sums across logins, and it names the providers it spans (CANONICAL §5,
/// `Recap`).
public struct Recap: Sendable, Equatable {
    /// One provider's part of the range.
    public struct Part: Sendable, Equatable {
        /// The provider's id — a reference; its name is the provider's.
        public let provider: String
        /// The provider's total in the recap's unit.
        public let value: Double
        /// Its part of the range, 0…1.
        public let share: Double

        public init(provider: String, value: Double, share: Double) {
            self.provider = provider
            self.value = value
            self.share = share
        }
    }

    /// The days the recap sums — the range it was read for, which its header
    /// writes and a sender checks it against.
    public let range: DateRange
    /// The one unit every range offers: cost only when every provider that
    /// used anything, this range or the one before, offers cost — an unpriced
    /// provider would otherwise count as nothing — and tokens when not.
    public let unit: Days.Unit
    /// The range's total in `unit`.
    public let total: Double
    /// The change against the range before, as a fraction (0.2 is 20% more) —
    /// nil when nothing was used before.
    public let change: Double?
    /// The providers that used anything, largest first, ties by id.
    public let providers: [Part]
    /// The model leaned on most across every provider, or nil when none is named.
    public let topModel: ModelMix.Part?
    /// Every model the range names, largest first — the mix's read, for the
    /// report's model by model.
    public let models: [ModelMix.Part]
    /// The day that added up to the most across every provider, or nil when
    /// nothing was used.
    public let biggestDay: DayValue?
    /// Every day the merged range held, oldest first — the activity's read,
    /// for the report's day by day. None when the range held nothing: an
    /// empty range says so, never zeros.
    public let days: [DayValue]
    /// What caching saved over the range.
    public let cacheSavings: Decimal
    /// The time worked over the range.
    public let workingTime: TimeInterval
    /// The sessions over the range.
    public let sessions: Int
    /// The tokens beside a total read in another unit — nil when the total is
    /// already tokens, so the page never says one number twice.
    public let tokens: Double?
    /// Whether no provider used anything in the range.
    public let isEmpty: Bool

    /// - Parameters:
    ///   - range: the days `this` was read for.
    ///   - this: each provider's days in the range, by provider id.
    ///   - before: each provider's days in the range before it.
    public init(range: DateRange, this: [String: Days], before: [String: Days]) {
        let unit = Self.unit(of: Array(this.values) + Array(before.values))
        let total = this.values.reduce(0) { $0 + $1.total(in: unit) }
        let earlier = before.values.reduce(0) { $0 + $1.total(in: unit) }
        let week = Days.merged(Array(this.values))
        let mix = ModelMix(of: week, in: unit)
        let activity = DayActivity(of: week, in: unit)

        self.range = range
        self.unit = unit
        self.total = total
        change = earlier > 0 ? (total - earlier) / earlier : nil
        providers = this
            .map { (provider: $0.key, value: $0.value.total(in: unit)) }
            .filter { $0.value > 0 }
            .map { Part(provider: $0.provider, value: $0.value, share: $0.value / total) }
            .sorted { $0.value == $1.value ? $0.provider < $1.provider : $0.value > $1.value }
        topModel = mix.top
        models = mix.parts
        biggestDay = activity.busiest
        days = week.isEmpty ? [] : activity.days
        cacheSavings = week.cacheSavings
        workingTime = week.workingTime
        sessions = week.sessions
        tokens = unit == .tokens ? nil : week.total(in: .tokens)
        isEmpty = week.isEmpty
    }

    /// Cost when every range that holds anything offers it, tokens when not.
    private static func unit(of ranges: [Days]) -> Days.Unit {
        let used = ranges.filter { !$0.isEmpty }
        return !used.isEmpty && used.allSatisfy { $0.units.contains(.cost) } ? .cost : .tokens
    }
}
