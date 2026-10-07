import Kit
import Foundation
import Testing
@testable import ClaudeBar

/// What the popover prints about a refresh: which data source answered, and
/// which step failed — because each sends the person somewhere different
/// (USER_JOURNEYS F1, F2).
@Suite
struct RefreshReportTests {
    @Test
    func `should say when usage was updated and which data source answered`() {
        let report = RefreshReport(age: "2m ago", source: "RPC", error: nil, step: nil, hasUsage: true)

        #expect(report.freshness == "Updated 2m ago · via RPC")
        #expect(report.failure == nil)
        #expect(report.isLastSeen == false)
    }

    @Test
    func `should keep the last usage marked last seen, and say the key couldn't be read, when a refresh fails at the key`() {
        let report = RefreshReport(
            age: "3h ago", source: "API",
            error: UsageError.SessionExpired(hint: "Run `codex` in terminal to log in again."), step: .lookup,
            hasUsage: true
        )

        #expect(report.freshness == "Last seen 3h ago · via API")
        #expect(report.isLastSeen)
        #expect(report.failure?.headline == "Couldn't read your key")
        #expect(report.failure?.detail.contains("Run `codex` in terminal to log in again.") == true)
    }

    @Test
    func `should headline each failed step differently, so the person knows where to look`() {
        #expect(RefreshReport.headline(for: .lookup) == "Couldn't read your key")
        #expect(RefreshReport.headline(for: .fetch) == "Couldn't connect")
        #expect(RefreshReport.headline(for: .mapping) == "Couldn't find the numbers")
    }

    @Test
    func `should show only the error's message when no step is known to have failed`() {
        let report = RefreshReport(
            age: nil, source: nil,
            error: UsageError.ExecutionFailed(reason: "Codex CLI session not checked."), step: nil, hasUsage: false
        )

        #expect(report.freshness == nil)
        #expect(report.failure?.headline == nil)
        #expect(report.failure?.detail == "Codex CLI session not checked.")
    }
}
