import Foundation
import Testing
@testable import Quotas

/// A project is where the work went: the working directory's last path
/// component, named once at aggregation — never the absolute path. Two lines
/// of one project add up to one (quota-by-project design §2–3).
@Suite
struct ProjectUsageLineTests {
    @Test func `should name a project by the working directory's last path component`() {
        #expect(ProjectUsageLine.name(of: "/Users/me/workspaces/ClaudeBar/marron") == "marron")
        #expect(ProjectUsageLine.name(of: "~/code/api") == "api")
    }

    @Test func `should name a directory with a trailing slash by its last folder`() {
        #expect(ProjectUsageLine.name(of: "/Users/me/code/marron/") == "marron")
    }

    @Test func `should read a directory with no folder in it as itself`() {
        #expect(ProjectUsageLine.name(of: "/") == "/")
        #expect(ProjectUsageLine.name(of: "marron") == "marron")
    }

    @Test func `should read a project's name on a tight row as it is, the unnamed one as a dash`() {
        #expect(ProjectUsageLine(project: "marron").displayName == "marron")
        #expect(ProjectUsageLine(project: "").displayName == "—")
    }

    @Test func `should add two lines of one project into one line`() {
        let sum = ProjectUsageLine(project: "marron", inputTokens: 1_000, outputTokens: 200, totalTokens: 1_200, cost: 1.5)
            + ProjectUsageLine(project: "marron", outputTokens: 100, cacheReadTokens: 500, totalTokens: 100, cost: 0.5)

        #expect(sum == ProjectUsageLine(project: "marron", inputTokens: 1_000, outputTokens: 300,
                                        cacheReadTokens: 500, totalTokens: 1_300, cost: 2))
    }
}
