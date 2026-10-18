import Testing
import Foundation
@testable import Domain

@Suite
struct NotchActivityResolverTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let resolver = NotchActivityResolver(finishedDisplayDuration: 4)

    private func running(_ id: String, startedAt: Date? = nil) -> ClaudeSession {
        ClaudeSession(id: id, cwd: "/Users/me/github/\(id)", startedAt: startedAt ?? now.addingTimeInterval(-60))
    }

    private func quota(_ percentRemaining: Double, provider: String = "claude") -> UsageQuota {
        UsageQuota(percentRemaining: percentRemaining, quotaType: .session, providerId: provider)
    }

    // MARK: - Nothing to say

    @Test
    func `should show nothing in the notch when no session runs and no quota is known`() {
        #expect(resolver.resolve(sessions: [], quotas: [], headlineQuota: nil, now: now) == nil)
    }

    @Test
    func `should show nothing in the notch for a healthy quota that is not the headline`() {
        #expect(resolver.resolve(sessions: [], quotas: [quota(80)], headlineQuota: nil, now: now) == nil)
    }

    @Test
    func `should show nothing in the notch for a quota only in warning`() {
        // 35% remaining is QuotaStatus.warning — visible in the popover, not in the notch.
        #expect(resolver.resolve(sessions: [], quotas: [quota(35)], headlineQuota: nil, now: now) == nil)
    }

    // MARK: - Session phases

    @Test
    func `should show a running session as working`() {
        let result = resolver.resolve(sessions: [running("claudebar")], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .working(running("claudebar")))
    }

    @Test
    func `should show a session with a running subagent as agents working`() {
        var session = running("claudebar")
        session.subagentStarted()

        let result = resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.activeSubagentCount == 1)
        #expect(result == .agentsWorking(session))
    }

    @Test
    func `should show a blocked session as awaiting input, with its pending prompt`() {
        var session = running("claudebar")
        session.awaitInput("Bash · rm -rf build/", at: now)

        let result = resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .awaitingInput(session))
        #expect(result?.session?.pendingPrompt == "Bash · rm -rf build/")
    }

    // MARK: - Priority

    @Test
    func `should show the blocked session over any number of working sessions`() {
        var blocked = running("claudebar", startedAt: now.addingTimeInterval(-10))
        blocked.awaitInput("Write · Package.swift", at: now)

        var busy = running("asc")
        busy.subagentStarted()
        busy.subagentStarted()

        let result = resolver.resolve(sessions: [busy, running("billfold"), blocked], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }

    @Test
    func `should show a critical quota over a working session`() {
        let result = resolver.resolve(sessions: [running("claudebar")], quotas: [quota(5)], headlineQuota: nil, now: now)

        #expect(result == .quotaThreshold(quota(5)))
    }

    @Test
    func `should show a blocked session over a critical quota`() {
        var blocked = running("claudebar")
        blocked.awaitInput("Bash · git push", at: now)

        let result = resolver.resolve(sessions: [blocked], quotas: [quota(0)], headlineQuota: nil, now: now)

        #expect(result == .awaitingInput(blocked))
    }

    @Test
    func `should show the lowest quota when several are past the threshold`() {
        let result = resolver.resolve(
            sessions: [],
            quotas: [quota(18, provider: "copilot"), quota(3, provider: "claude"), quota(60, provider: "codex")],
            headlineQuota: nil,
            now: now
        )

        #expect(result == .quotaThreshold(quota(3, provider: "claude")))
    }

    @Test
    func `should show the longest-running blocked session when several are blocked`() {
        var early = running("claudebar", startedAt: now.addingTimeInterval(-600))
        early.awaitInput("Bash · make", at: now)
        var late = running("asc", startedAt: now.addingTimeInterval(-30))
        late.awaitInput("Bash · ls", at: now)

        let result = resolver.resolve(sessions: [late, early], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }

    // MARK: - The idle glance

    @Test
    func `should show the headline quota at a glance when nothing is happening`() {
        // ClaudeBar is a quota monitor. With no session running, how much is
        // left is still the thing the user came for.
        let headline = quota(86)

        let result = resolver.resolve(sessions: [], quotas: [headline], headlineQuota: headline, now: now)

        #expect(result == .quotaGlance(headline))
    }

    @Test
    func `should glance at the chosen headline quota even when another quota is lower`() {
        let headline = quota(86, provider: "claude")
        let lower = quota(55, provider: "codex")

        let result = resolver.resolve(
            sessions: [],
            quotas: [lower, headline],
            headlineQuota: headline,
            now: now
        )

        #expect(result == .quotaGlance(headline))
    }

    @Test
    func `should show a working session over the headline glance`() {
        let headline = quota(86)

        let result = resolver.resolve(
            sessions: [running("claudebar")],
            quotas: [headline],
            headlineQuota: headline,
            now: now
        )

        #expect(result == .working(running("claudebar")))
    }

    @Test
    func `should show a quota past the threshold over the headline glance`() {
        let headline = quota(86, provider: "claude")
        let critical = quota(4, provider: "codex")

        let result = resolver.resolve(
            sessions: [],
            quotas: [headline, critical],
            headlineQuota: headline,
            now: now
        )

        #expect(result == .quotaThreshold(critical))
    }

    @Test
    func `should show no glance before the first quotas arrive`() {
        #expect(resolver.resolve(sessions: [], quotas: [], headlineQuota: nil, now: now) == nil)
    }

    // MARK: - The finished flash

    @Test
    func `should show a session that just stopped as finished`() {
        var session = running("claudebar")
        session.stop(at: now.addingTimeInterval(-1))

        let result = resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .finished(session))
    }

    @Test
    func `should show an ended session as finished for four seconds`() {
        var session = running("claudebar")
        session.end(at: now.addingTimeInterval(-3))

        #expect(resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now) == .finished(session))
    }

    @Test
    func `should stop showing finished once four seconds have passed`() {
        var session = running("claudebar")
        session.end(at: now.addingTimeInterval(-5))

        #expect(resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now) == nil)
    }

    @Test
    func `should show the next working session once the finished flash has passed`() {
        var done = running("claudebar")
        done.end(at: now.addingTimeInterval(-30))
        let stillGoing = running("asc")

        let result = resolver.resolve(sessions: [done, stillGoing], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .working(stillGoing))
    }

    @Test
    func `should briefly show a just-finished session over one still working`() {
        var done = running("claudebar")
        done.end(at: now.addingTimeInterval(-1))

        let result = resolver.resolve(sessions: [done, running("asc")], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }

    @Test
    func `should show a blocked session over a finished flash`() {
        var done = running("asc")
        done.end(at: now)
        var blocked = running("claudebar")
        blocked.awaitInput("Bash · rm", at: now)

        let result = resolver.resolve(sessions: [done, blocked], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }
}
