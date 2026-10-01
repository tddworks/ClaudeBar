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
    func `no sessions and no quotas resolves to nothing`() {
        #expect(resolver.resolve(sessions: [], quotas: [], headlineQuota: nil, now: now) == nil)
    }

    @Test
    func `a healthy quota that is not the headline resolves to nothing`() {
        #expect(resolver.resolve(sessions: [], quotas: [quota(80)], headlineQuota: nil, now: now) == nil)
    }

    @Test
    func `a warning quota does not take over the notch`() {
        // 35% remaining is QuotaStatus.warning — visible in the popover, not in the notch.
        #expect(resolver.resolve(sessions: [], quotas: [quota(35)], headlineQuota: nil, now: now) == nil)
    }

    // MARK: - Session phases

    @Test
    func `an active session resolves to working`() {
        let result = resolver.resolve(sessions: [running("claudebar")], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .working(running("claudebar")))
    }

    @Test
    func `a session with subagents resolves to agents working`() {
        var session = running("claudebar")
        session.subagentStarted()

        let result = resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.activeSubagentCount == 1)
        #expect(result == .agentsWorking(session))
    }

    @Test
    func `a blocked session resolves to awaiting input`() {
        var session = running("claudebar")
        session.awaitInput("Bash · rm -rf build/", at: now)

        let result = resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .awaitingInput(session))
        #expect(result?.session?.pendingPrompt == "Bash · rm -rf build/")
    }

    // MARK: - Priority

    @Test
    func `a blocked session outranks any number of working sessions`() {
        var blocked = running("claudebar", startedAt: now.addingTimeInterval(-10))
        blocked.awaitInput("Write · Package.swift", at: now)

        var busy = running("asc")
        busy.subagentStarted()
        busy.subagentStarted()

        let result = resolver.resolve(sessions: [busy, running("billfold"), blocked], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }

    @Test
    func `a critical quota outranks a working session`() {
        let result = resolver.resolve(sessions: [running("claudebar")], quotas: [quota(5)], headlineQuota: nil, now: now)

        #expect(result == .quotaThreshold(quota(5)))
    }

    @Test
    func `a blocked session outranks a critical quota`() {
        var blocked = running("claudebar")
        blocked.awaitInput("Bash · git push", at: now)

        let result = resolver.resolve(sessions: [blocked], quotas: [quota(0)], headlineQuota: nil, now: now)

        #expect(result == .awaitingInput(blocked))
    }

    @Test
    func `the most severe quota wins when several are past the threshold`() {
        let result = resolver.resolve(
            sessions: [],
            quotas: [quota(18, provider: "copilot"), quota(3, provider: "claude"), quota(60, provider: "codex")],
            headlineQuota: nil,
            now: now
        )

        #expect(result == .quotaThreshold(quota(3, provider: "claude")))
    }

    @Test
    func `among blocked sessions the one waiting longest wins`() {
        var early = running("claudebar", startedAt: now.addingTimeInterval(-600))
        early.awaitInput("Bash · make", at: now)
        var late = running("asc", startedAt: now.addingTimeInterval(-30))
        late.awaitInput("Bash · ls", at: now)

        let result = resolver.resolve(sessions: [late, early], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }

    // MARK: - The idle glance

    @Test
    func `the headline quota is shown at a glance when nothing is happening`() {
        // ClaudeBar is a quota monitor. With no session running, how much is
        // left is still the thing the user came for.
        let headline = quota(86)

        let result = resolver.resolve(sessions: [], quotas: [headline], headlineQuota: headline, now: now)

        #expect(result == .quotaGlance(headline))
    }

    @Test
    func `the glance shows the chosen quota even when another one is lower`() {
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
    func `a working session takes the notch back from the glance`() {
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
    func `a quota past the threshold outranks the glance`() {
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
    func `there is nothing to glance at before the first probe returns`() {
        #expect(resolver.resolve(sessions: [], quotas: [], headlineQuota: nil, now: now) == nil)
    }

    // MARK: - The finished flash

    @Test
    func `a session that just stopped resolves to finished`() {
        var session = running("claudebar")
        session.stop(at: now.addingTimeInterval(-1))

        let result = resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .finished(session))
    }

    @Test
    func `an ended session resolves to finished inside the display window`() {
        var session = running("claudebar")
        session.end(at: now.addingTimeInterval(-3))

        #expect(resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now) == .finished(session))
    }

    @Test
    func `finished expires once the display window has passed`() {
        var session = running("claudebar")
        session.end(at: now.addingTimeInterval(-5))

        #expect(resolver.resolve(sessions: [session], quotas: [], headlineQuota: nil, now: now) == nil)
    }

    @Test
    func `an expired finished session yields to the next activity`() {
        var done = running("claudebar")
        done.end(at: now.addingTimeInterval(-30))
        let stillGoing = running("asc")

        let result = resolver.resolve(sessions: [done, stillGoing], quotas: [], headlineQuota: nil, now: now)

        #expect(result == .working(stillGoing))
    }

    @Test
    func `finished briefly outranks a session that is still working`() {
        var done = running("claudebar")
        done.end(at: now.addingTimeInterval(-1))

        let result = resolver.resolve(sessions: [done, running("asc")], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }

    @Test
    func `a blocked session is never masked by a finished flash`() {
        var done = running("asc")
        done.end(at: now)
        var blocked = running("claudebar")
        blocked.awaitInput("Bash · rm", at: now)

        let result = resolver.resolve(sessions: [done, blocked], quotas: [], headlineQuota: nil, now: now)

        #expect(result?.session?.id == "claudebar")
    }
}
