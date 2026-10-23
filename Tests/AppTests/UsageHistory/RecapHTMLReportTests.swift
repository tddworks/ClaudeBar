import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The recap written out as one HTML file: what the card says, in the card's
/// words, plus the day-by-day and model-by-model shape read from their own
/// owners — self-contained, no script, everything escaped.
@Suite
struct RecapHTMLReportTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private let monday = Date(timeIntervalSince1970: 1_760_000_000)
    private let tuesday = Date(timeIntervalSince1970: 1_760_086_400)
    private let large = ModelUsageLine(model: "acme-large-2", totalTokens: 100, cost: 12)
    private let small = ModelUsageLine(model: "acme-small-1", totalTokens: 400, cost: 2)

    /// A priced day with the plain sums a report tells beside a total.
    private func day(_ date: Date, cost: Decimal, tokens: Int = 10, lines: [ModelUsageLine] = []) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: tokens, workingTime: 3_600,
                       sessionCount: 2, cachedSavings: 1, lines: lines)
    }

    private func priced(_ stats: DailyUsageStat...) -> Days { Days(stats, knowsCost: true) }

    /// The days a recap was read for.
    private var week: DateRange { DateRange.week(containing: monday, calendar: calendar) }

    private func read(this: [String: Days], before: [String: Days] = [:]) -> Recap {
        Recap(range: week, this: this, before: before)
    }

    private func report(_ recap: Recap, range: RecapRange = .this(.week)) -> RecapHTMLReport {
        RecapHTMLReport(recap: recap, range: range, name: { $0 })
    }

    private var twoProviders: Recap {
        read(this: ["a": priced(day(monday, cost: 15)), "b": priced(day(tuesday, cost: 5))],
              before: ["a": priced(day(monday, cost: 10))])
    }

    @Test func `should tell the total in the recap's unit, and what it is compared with`() {
        let html = report(twoProviders).html

        #expect(html.contains("$20.00"))
        #expect(html.contains("+100%"))
        #expect(html.contains("This week"))
        #expect(html.contains("vs last week"))
        #expect(html.contains("spent"))
    }

    @Test func `should name every provider with its value and share`() {
        let html = report(twoProviders).html

        #expect(html.contains("$15.00"))
        #expect(html.contains("$5.00"))
        #expect(html.contains("75%"))
        #expect(html.contains("25%"))
    }

    @Test func `should draw a bar for every day of the range, and mark the biggest one`() {
        let recap = read(this: ["a": priced(day(monday, cost: 9), day(tuesday, cost: 11))])
        let html = report(recap).html

        #expect(html.components(separatedBy: #"style="height:"#).count == 3)
        #expect(html.contains("peak"))
    }

    @Test func `should read every model the range names`() {
        let recap = read(this: ["a": priced(day(monday, cost: 12, lines: [large])),
                                 "b": priced(day(monday, cost: 2, lines: [small]))])
        let html = report(recap).html

        #expect(html.contains("large-2"))
        #expect(html.contains("small-1"))
    }

    @Test func `should tell the tokens beside a dollar total, the time worked and the sessions`() {
        let recap = read(this: ["a": priced(day(monday, cost: 12), day(tuesday, cost: 8))])
        let html = report(recap).html

        #expect(html.contains("20 tokens"))
        #expect(html.contains("2h 0m"))
        #expect(html.contains("4 sessions"))
    }

    @Test func `should write the days the recap sums`() {
        let october = DateRange.week(containing: calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!,
                                     calendar: calendar)
        let recap = Recap(range: october, this: ["a": priced(day(monday, cost: 1))], before: [:])

        #expect(report(recap).html.contains("2026"))
    }

    /// Two days that tie: the peak is the one the recap names its biggest day.
    @Test func `should mark only the recap's biggest day as the peak when two days tie`() {
        let recap = read(this: ["a": priced(day(monday, cost: 10), day(tuesday, cost: 10))])

        #expect(report(recap).html.components(separatedBy: "day peak").count == 2)
    }

    /// A model reads the hue the app's chart and mix give it: its place among
    /// the range's models in name order — not its place in the mix.
    @Test func `should colour each model as the app does`() {
        let big = ModelUsageLine(model: "zeta-big", totalTokens: 100, cost: 20)
        let little = ModelUsageLine(model: "alpha-little", totalTokens: 100, cost: 1)
        let recap = read(this: ["a": priced(day(monday, cost: 21, lines: [big, little]))])
        let html = report(recap).html

        #expect(html.contains(#"<span class="dot c1"></span><span class="name">\#(little.displayName)<"#))
        #expect(html.contains(#"<span class="dot c2"></span><span class="name">\#(big.displayName)<"#))
    }

    @Test func `should write the app's palette for light and for dark`() {
        let html = report(twoProviders).html

        #expect(html.contains(".c1{background:\(ModelColors.hex(ModelColors.palette[0], dark: false))}"))
        #expect(html.contains(".c1{background:\(ModelColors.hex(ModelColors.palette[0], dark: true))}"))
    }

    @Test func `should escape the names it writes`() {
        let sneaky = ModelUsageLine(model: "<em>opus</em>", totalTokens: 100, cost: 12)
        let recap = read(this: ["<script>alert(1)</script>": priced(day(monday, cost: 12, lines: [sneaky]))])
        let html = report(recap).html

        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script"))
        #expect(html.contains("&lt;em&gt;"))
        #expect(!html.contains("<em>"))
    }

    @Test func `should travel alone — its own stylesheet, no script, light and dark`() {
        let html = report(twoProviders).html

        #expect(html.contains("<style"))
        #expect(html.contains("prefers-color-scheme"))
        #expect(!html.contains("<script"))
    }

    @Test func `should say the range held nothing when it did`() {
        let recap = read(this: ["a": priced(DailyUsageStat.empty(for: monday))])

        #expect(report(recap).html.contains("Nothing this week."))
    }

    @Test func `should say the month's words when the range is a month`() {
        let html = report(twoProviders, range: .last(.month)).html

        #expect(html.contains("Last month"))
        #expect(html.contains("vs the month before"))
        #expect(html.contains("The month"))
    }

    /// An empty range is said, never zeros — and with nothing to compare, no
    /// change is written either.
    @Test func `should say an empty month held nothing`() {
        let recap = read(this: ["a": priced(DailyUsageStat.empty(for: monday))])

        #expect(report(recap, range: .last(.month)).html.contains("Nothing last month."))
    }
}
