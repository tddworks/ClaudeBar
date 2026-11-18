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
        /// Its change against the range before, as the recap's own — nil when
        /// it used nothing before.
        public let change: Double?

        public init(provider: String, value: Double, share: Double, change: Double? = nil) {
            self.provider = provider
            self.value = value
            self.share = share
            self.change = change
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
    /// Every project the range names and what remains unnamed, largest first
    /// — the split's read, for the report's project by project. None when no
    /// log names a project.
    public let projects: [ByProject.Part]
    /// Every provider's days in the range as one — what the report reads a
    /// day's own figures from.
    public let whole: Days
    /// The units the recap can be read in (`read(in:)`), its own first: a
    /// unit every provider offers and the range holds something in — never
    /// cost when the recap itself reads in tokens.
    public let units: [Days.Unit]
    /// The days of the range that held anything.
    public let activeDays: Int

    /// Each provider's days in the range and in the one before, as read.
    private let this: [String: Days]
    private let before: [String: Days]
    /// The range before, every provider's days as one.
    private let wholeBefore: Days

    /// - Parameters:
    ///   - range: the days `this` was read for.
    ///   - this: each provider's days in the range, by provider id.
    ///   - before: each provider's days in the range before it.
    public init(range: DateRange, this: [String: Days], before: [String: Days]) {
        self.init(range: range, this: this, before: before,
                  in: Self.unit(of: Array(this.values) + Array(before.values)))
    }

    private init(range: DateRange, this: [String: Days], before: [String: Days], in unit: Days.Unit) {
        let own = Self.unit(of: Array(this.values) + Array(before.values))
        let total = this.values.reduce(0) { $0 + $1.total(in: unit) }
        let earlier = before.values.reduce(0) { $0 + $1.total(in: unit) }
        let week = Days.merged(Array(this.values))
        let mix = ModelMix(of: week, in: unit)
        let split = ByProject(of: week, in: unit)
        let activity = DayActivity(of: week, in: unit)

        self.range = range
        self.unit = unit
        self.total = total
        self.this = this
        self.before = before
        whole = week
        wholeBefore = Days.merged(Array(before.values))
        change = Self.change(from: earlier, to: total)
        providers = this
            .map { (provider: $0.key, value: $0.value.total(in: unit)) }
            .filter { $0.value > 0 }
            .map { Part(provider: $0.provider, value: $0.value, share: $0.value / total,
                        change: Self.change(from: before[$0.provider]?.total(in: unit) ?? 0, to: $0.value)) }
            .sorted { $0.value == $1.value ? $0.provider < $1.provider : $0.value > $1.value }
        topModel = mix.top
        models = mix.parts
        projects = split.isEmpty ? [] : split.parts
        biggestDay = activity.busiest
        days = week.isEmpty ? [] : activity.days
        cacheSavings = week.cacheSavings
        workingTime = week.workingTime
        sessions = week.sessions
        tokens = unit == .tokens ? nil : week.total(in: .tokens)
        isEmpty = week.isEmpty
        activeDays = week.activeDays
        units = [own] + Days.Unit.allCases.filter { $0 != own && $0 != .cost && week.total(in: $0) > 0 }
    }

    /// The same range read in another unit it offers — every figure, the
    /// change and the order follow. A unit it doesn't offer reads as it is.
    public func read(in unit: Days.Unit) -> Recap {
        guard unit != self.unit, units.contains(unit) else { return self }
        return Recap(range: range, this: this, before: before, in: unit)
    }

    /// A model's or a project's change against the range before, in the
    /// recap's unit — nil when it spent nothing before.
    public func change<Line: UsageLine>(of part: UsageMix<Line>.Part) -> Double? {
        let earlier = UsageMix<Line>(of: wholeBefore, in: unit).parts.first { $0.line.name == part.line.name }
        return Self.change(from: earlier?.value ?? 0, to: part.value)
    }

    /// The range's providers, in the range's order, each with its part of
    /// `date` — nothing for one that used nothing that day — so a list that
    /// switches from the range to a day keeps its rows where they were.
    public func providers(on date: Date) -> [Part] {
        let values = providers.map { part in
            this[part.provider]?.stats.first { $0.date == date }?.spend.value(in: unit) ?? 0
        }
        let day = values.reduce(0, +)
        return zip(providers, values).map {
            Part(provider: $0.provider, value: $1, share: day > 0 ? $1 / day : 0)
        }
    }

    /// The range's models or projects (`parts`), in the range's order, each
    /// with its part of `date` — the day's own mix, nothing for a line the
    /// day didn't hold.
    public func parts<Line: UsageLine>(of parts: [UsageMix<Line>.Part], on date: Date) -> [UsageMix<Line>.Part] {
        let day = UsageMix<Line>(of: Days(whole.stats.filter { $0.date == date }, knowsCost: whole.knowsCost), in: unit)
        return parts.map { part in
            day.parts.first { $0.line.name == part.line.name }
                ?? UsageMix<Line>.Part(line: Line(name: part.line.name, spend: .none), value: 0, share: 0)
        }
    }

    /// The total over the days that held anything — nil when none did.
    public var dailyAverage: Double? { activeDays > 0 ? total / Double(activeDays) : nil }

    /// The total over the sessions — nil when the logs count none.
    public var perSession: Double? { sessions > 0 ? total / Double(sessions) : nil }

    /// A change against what came before, as a fraction — nil when nothing
    /// came before.
    private static func change(from earlier: Double, to value: Double) -> Double? {
        earlier > 0 ? (value - earlier) / earlier : nil
    }

    /// Cost when every range that holds anything offers it, tokens when not.
    private static func unit(of ranges: [Days]) -> Days.Unit {
        let used = ranges.filter { !$0.isEmpty }
        return !used.isEmpty && used.allSatisfy { $0.units.contains(.cost) } ? .cost : .tokens
    }
}
