import Foundation
import Quotas
import DataSources
import Providers
import Monitoring

/// What the recap's report shows, in every unit the recap offers: each figure
/// already read from its owner (`Recap`, `ModelMix`, `ByProject`,
/// `DayActivity`) and already written in the card's words (`UsageFormat`), so
/// the page's markup and its script only show — neither counts, compares or
/// formats. A number beside a word (`amount`, `share`) is there to sort a
/// list or size a bar, never to be printed.
struct RecapReportPage: Encodable {
    /// A unit the page can be read in.
    struct Unit: Encodable {
        let id: String
        let name: String
    }

    /// A change against the range before: its words, and which way it went.
    struct Change: Encodable {
        let text: String
        let up: Bool
        let amount: Double
    }

    /// One line of a split over the range — a provider, a model, a project.
    struct Row: Encodable {
        let name: String
        let hue: String
        let value: String
        let amount: Double
        let share: Double
        let shareText: String
        let change: Change?
    }

    /// The range split by something.
    struct Split: Encodable {
        let id: String
        let title: String
        /// The split's name on the chart's choice.
        let by: String
        let rows: [Row]
    }

    /// A named figure — a highlight, or one of a day's own.
    struct Fact: Encodable {
        let k: String
        let v: String
    }

    /// A split's row on one day: which of the split's rows it is, its value
    /// and its part of the day.
    struct DayPart: Encodable {
        let row: Int
        let value: String
        let amount: Double
        let share: Double
        let shareText: String
    }

    /// One day in a unit: its value, how full it is against the busiest, and
    /// what it held of every split — only the rows the day used, in the
    /// split's order.
    struct Day: Encodable {
        let value: String
        let share: Double
        let peak: Bool
        let parts: [[DayPart]]
    }

    /// One hour that held something: the hour of the day, its shading band
    /// (`UsageHeatmap`'s, 1…4) and its value.
    struct HourCell: Encodable {
        let h: Int
        let level: Int
        let value: String
    }

    /// One day hour by hour — only the hours that held something — or a day
    /// whose hours were never kept.
    struct HourRow: Encodable {
        let known: Bool
        let cells: [HourCell]
    }

    /// The range hour by hour: a row a day, the hours of the day added up
    /// over the range, and the busiest hour in words.
    struct Hours: Encodable {
        let rows: [HourRow]
        let ofDay: [HourCell]
        let peak: String
    }

    /// The whole recap read in one unit.
    struct View: Encodable {
        let total: String
        let caption: String
        let change: Change?
        let subline: [String]
        let tiles: [Fact]
        let splits: [Split]
        let days: [Day]
        /// None when no day of the range knows its hours.
        let hours: Hours?
    }

    /// A day's own figures, whatever the unit: its label under a bar, its
    /// full name, and what it held.
    struct DayFacts: Encodable {
        let label: String
        let title: String
        let facts: [Fact]
    }

    /// The unit the page opens on — the recap's own.
    let unit: String
    let units: [Unit]
    /// The period's word, *week* or *month*.
    let period: String
    /// What a change is against.
    let compared: String
    let days: [DayFacts]
    /// The range's tokens by kind; none when the logs keep only a total.
    let tokens: [Fact]
    let views: [String: View]

    /// The view the page opens on.
    var opening: View? { views[unit] }

    init(recap: Recap, range: RecapRange, name: (String) -> String) {
        let reads = recap.units.map { recap.read(in: $0) }
        // A provider keeps its hue from unit to unit: its place in the
        // recap's own split, then any the other units add.
        let providers = reads.flatMap { $0.providers.map(\.provider) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        unit = Self.id(recap.unit)
        units = recap.units.map { Unit(id: Self.id($0), name: $0.label) }
        period = range.period.word
        compared = range.comparedWith
        days = recap.isEmpty ? [] : recap.whole.stats.map {
            Self.facts(of: $0, in: range.period, priced: recap.units.contains(.cost))
        }
        tokens = Self.kinds(of: recap.whole.spend)
        views = Dictionary(uniqueKeysWithValues: reads.map {
            (Self.id($0.unit), Self.view(of: $0, providers: providers, name: name))
        })
    }

    // MARK: - A view

    private static func view(of recap: Recap, providers: [String], name: (String) -> String) -> View {
        let unit = recap.unit
        let models = recap.models.map(\.line.model)
        let projects = recap.projects.map(\.line.project).filter { !$0.isEmpty }.sorted()

        let byProvider = Split(id: "provider", title: "Where it went", by: "Provider", rows: recap.providers.map {
            row(name($0.provider), hue: providers.firstIndex(of: $0.provider).map(hue) ?? "cu",
                value: $0.value, share: $0.share, change: $0.change, in: unit)
        })
        let byModel = Split(id: "model", title: "Models", by: "Model", rows: recap.models.map {
            row($0.line.displayName, hue: ModelColors.index(of: $0.line.model, among: models).map(hue) ?? "cu",
                value: $0.value, share: $0.share, change: recap.change(of: $0), in: unit)
        })
        let byProject = Split(id: "project", title: "Projects", by: "Project", rows: recap.projects.map {
            row($0.line.displayName, hue: projects.firstIndex(of: $0.line.project).map(hue) ?? "cu",
                value: $0.value, share: $0.share, change: recap.change(of: $0), in: unit)
        })

        var subline: [String] = []
        if let tokens = recap.tokens { subline.append("\(UsageFormat.count(Int(tokens))) tokens") }
        if recap.workingTime > 0 { subline.append(UsageFormat.duration(recap.workingTime)) }
        if recap.sessions > 0 { subline.append("\(recap.sessions) sessions") }

        return View(
            total: UsageFormat.value(recap.total, in: unit),
            caption: unit.caption,
            change: recap.change.map(change),
            subline: subline,
            tiles: tiles(of: recap),
            splits: [byProvider, byModel, byProject].filter { !$0.rows.isEmpty },
            days: recap.days.map { day in
                Day(value: UsageFormat.value(day.value, in: unit), share: day.share,
                    peak: day.date == recap.biggestDay?.date,
                    parts: [
                        byProvider.rows.isEmpty ? nil : parts(recap.providers(on: day.date).map { ($0.value, $0.share) }, in: unit),
                        byModel.rows.isEmpty ? nil : parts(recap.parts(of: recap.models, on: day.date).map { ($0.value, $0.share) }, in: unit),
                        byProject.rows.isEmpty ? nil : parts(recap.parts(of: recap.projects, on: day.date).map { ($0.value, $0.share) }, in: unit),
                    ].compactMap { $0 })
            },
            hours: hours(of: recap.hours, in: unit))
    }

    /// The hour by hour, or nothing when no day knows its hours.
    private static func hours(of activity: HourActivity, in unit: Days.Unit) -> Hours? {
        guard let busiest = activity.busiest else { return nil }
        func cells(_ hours: [HourActivity.Hour]) -> [HourCell] {
            hours.filter { $0.value > 0 }.map {
                HourCell(h: $0.hour, level: UsageHeatmap.level(ofShare: $0.share),
                         value: UsageFormat.value($0.value, in: unit))
            }
        }
        let day = busiest.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return Hours(rows: activity.days.map { HourRow(known: $0.isKnown, cells: cells($0.hours)) },
                     ofDay: cells(activity.ofDay),
                     peak: "\(day), \(span(busiest.hour.hour)) · \(UsageFormat.value(busiest.hour.value, in: unit))")
    }

    /// An hour of the day as the span it covers — "14:00–15:00".
    static func span(_ hour: Int) -> String {
        String(format: "%02d:00–%02d:00", hour, (hour + 1) % 24)
    }

    private static func tiles(of recap: Recap) -> [Fact] {
        var tiles: [Fact] = []
        if let model = recap.topModel { tiles.append(Fact(k: "Top model", v: model.line.displayName)) }
        if let day = recap.biggestDay {
            tiles.append(Fact(k: "Biggest day", v: day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())))
        }
        if recap.activeDays > 0 { tiles.append(Fact(k: "Active days", v: "\(recap.activeDays) of \(recap.days.count)")) }
        if let average = recap.dailyAverage {
            tiles.append(Fact(k: "Per active day", v: UsageFormat.value(average, in: recap.unit)))
        }
        if let each = recap.perSession {
            tiles.append(Fact(k: "Per session", v: UsageFormat.value(each, in: recap.unit)))
        }
        if recap.cacheSavings > 0 { tiles.append(Fact(k: "Cache saved", v: UsageFormat.money(recap.cacheSavings))) }
        let hit = recap.whole.spend.cacheHitRate
        if hit > 0 { tiles.append(Fact(k: "Cache hit rate", v: UsageFormat.share(hit))) }
        return tiles
    }

    // MARK: - The days and the tokens, whatever the unit

    private static func facts(of day: DailyUsageStat, in period: RecapPeriod, priced: Bool) -> DayFacts {
        var facts: [Fact] = []
        if priced, day.totalCost > 0 { facts.append(Fact(k: "Cost", v: UsageFormat.money(day.totalCost))) }
        if day.totalTokens > 0 { facts.append(Fact(k: "Tokens", v: UsageFormat.count(day.totalTokens))) }
        if day.sessionCount > 0 { facts.append(Fact(k: "Sessions", v: "\(day.sessionCount)")) }
        if day.workingTime > 0 { facts.append(Fact(k: "Worked", v: UsageFormat.duration(day.workingTime))) }
        if day.cachedSavings > 0 { facts.append(Fact(k: "Cache saved", v: UsageFormat.money(day.cachedSavings))) }
        if day.cacheHitRate > 0 { facts.append(Fact(k: "Cache hit rate", v: UsageFormat.share(day.cacheHitRate))) }

        let label: String
        switch period {
        case .week: label = day.date.formatted(.dateTime.weekday(.abbreviated))
        case .month: label = day.date.formatted(.dateTime.day())
        }
        return DayFacts(label: label, title: day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                        facts: facts)
    }

    private static func kinds(of spend: Spend) -> [Fact] {
        [("Input", spend.inputTokens), ("Output", spend.outputTokens),
         ("Cache write", spend.cacheCreationTokens), ("Cache read", spend.cacheReadTokens)]
            .filter { $0.1 > 0 }
            .map { Fact(k: $0.0, v: UsageFormat.count($0.1)) }
    }

    // MARK: - Words

    private static func row(_ name: String, hue: String, value: Double, share: Double, change: Double?,
                            in unit: Days.Unit) -> Row {
        Row(name: name, hue: hue, value: UsageFormat.value(value, in: unit), amount: value, share: share,
            shareText: UsageFormat.share(share), change: change.map(Self.change))
    }

    /// A day's parts of a split, row for row with the range's — written only
    /// for the rows the day used, each naming its row.
    private static func parts(_ day: [(value: Double, share: Double)], in unit: Days.Unit) -> [DayPart] {
        day.enumerated().filter { $0.element.value > 0 }.map { row, part in
            DayPart(row: row, value: UsageFormat.value(part.value, in: unit), amount: part.value, share: part.share,
                    shareText: UsageFormat.share(part.share))
        }
    }

    private static func change(_ change: Double) -> Change {
        Change(text: UsageFormat.change(change), up: change > 0, amount: change)
    }

    /// A unit's name in the page's data.
    private static func id(_ unit: Days.Unit) -> String { unit.label.lowercased() }

    /// The stylesheet's class for the palette's hue at `index`, cycled.
    static func hue(_ index: Int) -> String { "c\(index % ModelColors.palette.count + 1)" }
}
