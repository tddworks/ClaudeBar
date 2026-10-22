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

    private func day(_ date: Date, _ projects: [ProjectUsageLine]) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: projects.reduce(0) { $0 + $1.cost },
                       totalTokens: projects.reduce(0) { $0 + $1.totalTokens }, workingTime: 0, sessionCount: 1,
                       projects: projects)
    }

    @Test func `should sum each project over the range, largest first`() {
        let days = Days([day(monday, [marron, api]), day(tuesday, [api])], knowsCost: true)

        let byProject = ByProject(of: days, in: .cost)

        #expect(byProject.parts.map(\.line.project) == ["marron", "api"])
        #expect(byProject.parts.map(\.value) == [12, 4])
        #expect(byProject.parts.last?.line.totalTokens == 800)
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
}
