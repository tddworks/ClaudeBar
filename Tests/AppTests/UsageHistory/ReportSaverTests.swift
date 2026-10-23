import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// Where a report leaves the app: a write that lands holds the whole page, and
/// one that fails is kept for the card to say.
@MainActor
@Suite
struct ReportSaverTests {
    private let report: RecapHTMLReport = {
        let calendar = Calendar(identifier: .gregorian)
        let monday = Date(timeIntervalSince1970: 1_760_000_000)
        let days = Days([DailyUsageStat(date: monday, totalCost: 5, totalTokens: 10, workingTime: 0, sessionCount: 1)],
                        knowsCost: true)
        let recap = Recap(range: DateRange.week(containing: monday, calendar: calendar), this: ["a": days], before: [:])
        return RecapHTMLReport(recap: recap, range: .this(.week), name: { $0 })
    }()

    @Test func `should write the whole report where the person chose`() throws {
        let saver = ReportSaver()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recap-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: url) }

        saver.write(report, to: url)

        #expect(try String(contentsOf: url, encoding: .utf8) == report.html)
        #expect(saver.failure == nil)
    }

    @Test func `should keep why the save failed when the report cannot be written`() {
        let saver = ReportSaver()
        let nowhere = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/recap.html")

        saver.write(report, to: nowhere)

        #expect(saver.failure != nil)
    }

    @Test func `should forget the failure once the person dismissed it`() {
        let saver = ReportSaver()
        saver.write(report, to: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/recap.html"))

        saver.dismissFailure()

        #expect(saver.failure == nil)
    }
}
