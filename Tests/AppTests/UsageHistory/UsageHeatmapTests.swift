import Testing
import Foundation
import SwiftUI
import Domain
@testable import ClaudeBar

/// A range's heatmap lays every date of it out as one cell — an empty day an
/// empty cell, never a gap — so a view can draw it without deciding anything.
@Suite
struct UsageHeatmapTests {
    /// Sunday-first, so the rows a test asserts are the same everywhere.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }()

    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func range(_ count: Int) -> [DayValue] {
        (0..<count).map { offset in
            DayValue(date: start.addingTimeInterval(Double(offset) * 86_400),
                     value: Double(offset), share: 0)
        }
    }

    @Test func `should lay every date of the range out as one cell, in order`() {
        let days = range(365)
        let heatmap = UsageHeatmap(days, calendar: calendar)
        let cells = heatmap.weeks.flatMap { $0 }.compactMap { $0 }

        #expect(heatmap.weeks.allSatisfy { $0.count == 7 })
        #expect(cells.count == 365)
        #expect(cells.map(\.date) == days.map(\.date))
    }

    @Test func `should put each day in the row of its own weekday`() {
        let heatmap = UsageHeatmap(range(365), calendar: calendar)

        for week in heatmap.weeks {
            for (row, day) in week.enumerated() {
                guard let day else { continue }
                let weekday = calendar.component(.weekday, from: day.date)
                #expect(weekday == ((calendar.firstWeekday - 1 + row) % 7) + 1)
            }
        }
    }

    @Test func `should keep an empty day a cell, not a gap`() {
        let days = [DayValue(date: start, value: 10, share: 1),
                    DayValue(date: start.addingTimeInterval(86_400), value: 0, share: 0),
                    DayValue(date: start.addingTimeInterval(2 * 86_400), value: 5, share: 0.5)]
        let cells = UsageHeatmap(days, calendar: calendar).weeks.flatMap { $0 }.compactMap { $0 }

        #expect(cells.count == 3)
        #expect(cells[1].value == 0)
        #expect(UsageHeatmap.level(of: cells[1]) == 0)
    }

    @Test func `should shade a day by how full it is against the busiest`() {
        let shades = [1, 0, 0.5, 0.2].map {
            UsageHeatmap.level(of: DayValue(date: start, value: $0 * 10, share: $0))
        }

        #expect(shades == [4, 0, 2, 1])
    }

    @Test func `should leave every day unshaded when nothing was used`() {
        let idle = DayValue(date: start, value: 0, share: 0)

        #expect(UsageHeatmap.level(of: idle) == 0)
    }

    @Test func `should pad the week before the range's first day, never a day`() {
        let days = range(3)
        let heatmap = UsageHeatmap(days, calendar: calendar)
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7

        #expect(heatmap.weeks.first?.prefix(leading).allSatisfy { $0 == nil } == true)
        #expect(heatmap.weeks.first?[leading]?.date == start)
    }

    @Test func `should mark where each month starts, once, oldest first`() {
        let heatmap = UsageHeatmap(range(365), calendar: calendar)

        #expect(heatmap.monthMarks.count >= 12)
        #expect(heatmap.monthMarks.map(\.column) == heatmap.monthMarks.map(\.column).sorted())
        #expect(Set(heatmap.monthMarks.map(\.month)).count == heatmap.monthMarks.count)
        #expect(heatmap.monthMarks.allSatisfy { (0..<heatmap.weeks.count).contains($0.column) })
    }

    @Test func `should leave the first month unlabelled when the next starts within two columns`() {
        // A range starting Oct 25: November begins one column later, too
        // close for two 7 pt labels, so October's mark goes.
        let start = calendar.date(from: DateComponents(year: 2024, month: 10, day: 25))!
        let days = (0..<60).map { offset in
            DayValue(date: calendar.date(byAdding: .day, value: offset, to: start)!, value: 0, share: 0)
        }
        let heatmap = UsageHeatmap(days, calendar: calendar)
        let october = calendar.date(from: DateComponents(year: 2024, month: 10))!

        #expect(!heatmap.monthMarks.contains { $0.month == october })
        #expect(heatmap.monthMarks.contains { calendar.component(.month, from: $0.month) == 11 })
    }

    @Test func `should keep the first month's mark when the next starts three columns away`() {
        // A range starting Oct 7: November begins three columns later, room
        // enough for both labels.
        let start = calendar.date(from: DateComponents(year: 2024, month: 10, day: 7))!
        let days = (0..<60).map { offset in
            DayValue(date: calendar.date(byAdding: .day, value: offset, to: start)!, value: 0, share: 0)
        }
        let heatmap = UsageHeatmap(days, calendar: calendar)
        let october = calendar.date(from: DateComponents(year: 2024, month: 10))!

        #expect(heatmap.monthMarks.contains { $0.month == october })
    }

    @Test @MainActor func `should fit a year's heatmap inside the popover at every text size`() throws {
        let year = Days(range(365).map { value in
            DailyUsageStat(date: value.date, totalCost: Decimal(value.value), totalTokens: 0,
                           workingTime: 0, sessionCount: 1)
        }, knowsCost: true)

        for textSize in PopoverTextSize.allCases {
            let renderer = ImageRenderer(content: UsageInsightsHeatmapView(days: year)
                .environment(\.popoverTextSize, textSize))
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            #expect(CGFloat(image.width) <= textSize.popoverWidth, "\(textSize)")
        }
    }
}