import Foundation
import Testing
@testable import Quotas

/// Where the work went over a range: each project summed over it, largest
/// first in the unit asked, the unnamed part among them so the parts add up
/// to the range, each with its share (CANONICAL §5, `ByProject`).
@Suite
struct ByProjectTests {
    private let monday = Date(timeIntervalSince1970: 1_760_000_000)
    private let tuesday = Date(timeIntervalSince1970: 1_760_086_400)

    private let marron = ProjectUsageLine(project: "marron", inputTokens: 100, totalTokens: 120, cost: 12)
    private let api = ProjectUsageLine(project: "api", inputTokens: 300, totalTokens: 400, cost: 2)
    private let unnamed = ProjectUsageLine(project: "", totalTokens: 50, cost: 1)

    /// A day that is the sum of its project lines, the unnamed one among them.
    private func day(_ date: Date, _ projects: [ProjectUsageLine]) -> DailyUsageStat {
        let whole = projects.reduce(Spend.none) { $0 + $1.spend }
        return DailyUsageStat(date: date, totalCost: whole.cost, totalTokens: whole.totalTokens, workingTime: 0,
                              sessionCount: 1, inputTokens: whole.inputTokens, outputTokens: whole.outputTokens,
                              cacheCreationTokens: whole.cacheCreationTokens, cacheReadTokens: whole.cacheReadTokens,
                              projects: projects)
    }

    /// A day whose log named no directory: totals without a split.
    private func unsplitDay(_ date: Date, totalTokens: Int, cost: Decimal) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: cost, totalTokens: totalTokens, workingTime: 0, sessionCount: 1)
    }

    @Test func `should sum each project over the range, largest first`() {
        let days = Days([day(monday, [marron, api]), day(tuesday, [api])], knowsCost: true)

        let byProject = ByProject(of: days, in: .cost)

        #expect(byProject.parts.map(\.line.project) == ["marron", "api"])
        #expect(byProject.parts.map(\.value) == [12, 4])
        #expect(byProject.parts.last?.line.spend.totalTokens == 800)
    }

    @Test func `should rank the projects in the unit asked`() {
        let days = Days([day(monday, [marron, api])], knowsCost: true)

        #expect(ByProject(of: days, in: .tokens).parts.map(\.line.project) == ["api", "marron"])
    }

    @Test func `should keep the unnamed part in the read, so the parts add up to the range`() {
        let days = Days([day(monday, [marron, unnamed])], knowsCost: true)

        let byProject = ByProject(of: days, in: .cost)

        #expect(byProject.parts.map(\.line.project) == ["marron", ""])
        #expect(byProject.parts.reduce(0) { $0 + $1.value } == days.total(in: .cost))
    }

    /// A day whose records name no directory, on a range that names one, is
    /// the unnamed part of the range — otherwise the parts would overstate
    /// the named projects and not add up.
    @Test func `should count a day that names no project as the unnamed part, so the parts add up`() {
        let days = Days([day(monday, [marron, api]), unsplitDay(tuesday, totalTokens: 50, cost: 1)], knowsCost: true)

        let byProject = ByProject(of: days, in: .cost)

        #expect(byProject.parts.map(\.line.project) == ["marron", "api", ""])
        #expect(byProject.parts.reduce(0) { $0 + $1.value } == days.total(in: .cost))
    }

    @Test func `should give each project its share of the range`() {
        let big = ProjectUsageLine(project: "marron", cost: 3)
        let little = ProjectUsageLine(project: "api", cost: 1)

        let byProject = ByProject(of: Days([day(monday, [big, little])], knowsCost: true), in: .cost)

        #expect(byProject.parts.map(\.share) == [0.75, 0.25])
    }

    @Test func `should order projects that tie by name`() {
        let zed = ProjectUsageLine(project: "zed", cost: 2)
        let alpha = ProjectUsageLine(project: "alpha", cost: 2)

        let byProject = ByProject(of: Days([day(monday, [zed, alpha])], knowsCost: true), in: .cost)

        #expect(byProject.parts.map(\.line.project) == ["alpha", "zed"])
    }

    @Test func `should name the project used most as the top one`() {
        let days = Days([day(monday, [api, marron])], knowsCost: true)

        #expect(ByProject(of: days, in: .cost).top?.line.project == "marron")
    }

    /// The unnamed part is a part of the read, never a project, so it is
    /// never the top one.
    @Test func `should name the largest project as the top one when unnamed records spent more`() {
        let days = Days([day(monday, [api, ProjectUsageLine(project: "", totalTokens: 900, cost: 90)])], knowsCost: true)

        #expect(ByProject(of: days, in: .cost).top?.line.project == api.project)
    }

    @Test func `should have no top project and no share when nothing was used`() {
        let idle = ProjectUsageLine(project: "marron")

        let byProject = ByProject(of: Days([day(monday, [idle])], knowsCost: true), in: .cost)

        #expect(byProject.parts.map(\.share) == [0])
        #expect(ByProject(of: Days([], knowsCost: true), in: .cost).top == nil)
    }

    @Test func `should have no top project when no record names one`() {
        let days = Days([day(monday, [unnamed])], knowsCost: true)

        #expect(ByProject(of: days, in: .cost).top == nil)
    }

    /// Two ranges read as one (`Days.merged`, as the recap reads every
    /// provider's week) add a day with a split to a day of the same date
    /// without one: the second day's spend stays in the remainder, so no
    /// named project's share overstates.
    @Test func `should keep a merged day's unsplit spend in the unnamed part, so shares stay true`() {
        let claude = DailyUsageStat(date: monday, totalCost: 10, totalTokens: 100, workingTime: 0, sessionCount: 1,
                                    projects: [ProjectUsageLine(project: "marron", totalTokens: 60, cost: 6),
                                               ProjectUsageLine(project: "api", totalTokens: 20, cost: 2)])
        let codex = unsplitDay(monday, totalTokens: 100, cost: 10)

        let merged = Days.merged([Days([claude], knowsCost: true), Days([codex], knowsCost: true)])
        let byProject = ByProject(of: merged, in: .cost)

        #expect(byProject.parts.map(\.line.project) == ["", "marron", "api"])
        #expect(byProject.parts.map(\.share) == [0.6, 0.3, 0.1])
        #expect(byProject.top?.line.project == "marron")
    }

    @Test func `should name the range's projects in name order, the unnamed part apart`() {
        let days = Days([day(monday, [marron, unnamed, api]), unsplitDay(tuesday, totalTokens: 0, cost: 0)],
                        knowsCost: true)

        let byProject = ByProject(of: days, in: .cost)

        #expect(byProject.names == ["api", "marron"])
        #expect(!byProject.isEmpty)
    }

    @Test func `should be empty when no day names a project`() {
        let days = Days([day(monday, [unnamed]), unsplitDay(tuesday, totalTokens: 50, cost: 3)], knowsCost: true)

        let byProject = ByProject(of: days, in: .cost)

        #expect(byProject.names.isEmpty)
        #expect(byProject.isEmpty)
    }
}
