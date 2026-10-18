import Testing
import Foundation
@testable import Domain

@Suite
struct NotchActivityTests {
    private func session(_ id: String = "s1") -> ClaudeSession {
        ClaudeSession(id: id, cwd: "/Users/me/github/claudebar")
    }

    private func quota(_ percentRemaining: Double) -> UsageQuota {
        UsageQuota(percentRemaining: percentRemaining, quotaType: .session, providerId: "claude")
    }

    @Test
    func `should rank a session awaiting input above every other notch activity`() {
        let blocked = NotchActivity.awaitingInput(session())

        #expect(blocked > .finished(session()))
        #expect(blocked > .quotaThreshold(quota(2)))
        #expect(blocked > .agentsWorking(session()))
        #expect(blocked > .working(session()))
    }

    @Test
    func `should rank a finished session above quotas and work but below a blocked session`() {
        let finished = NotchActivity.finished(session())

        #expect(finished > .quotaThreshold(quota(2)))
        #expect(finished > .agentsWorking(session()))
        #expect(finished < .awaitingInput(session()))
    }

    @Test
    func `should rank a quota past the threshold above working sessions`() {
        let quotaActivity = NotchActivity.quotaThreshold(quota(2))

        #expect(quotaActivity > .agentsWorking(session()))
        #expect(quotaActivity > .working(session()))
    }

    @Test
    func `should rank a session with agents working above a plain working one`() {
        #expect(NotchActivity.agentsWorking(session()) > .working(session()))
    }

    @Test
    func `should rank the headline glance below every other notch activity`() {
        let glance = NotchActivity.quotaGlance(quota(86))

        #expect(glance < .working(session()))
        #expect(glance < .agentsWorking(session()))
        #expect(glance < .quotaThreshold(quota(2)))
        #expect(glance < .finished(session()))
        #expect(glance < .awaitingInput(session()))
    }

    @Test
    func `should name the session behind a session activity and none behind a quota`() {
        #expect(NotchActivity.working(session("a")).session?.id == "a")
        #expect(NotchActivity.agentsWorking(session("b")).session?.id == "b")
        #expect(NotchActivity.awaitingInput(session("c")).session?.id == "c")
        #expect(NotchActivity.finished(session("d")).session?.id == "d")
        #expect(NotchActivity.quotaThreshold(quota(2)).session == nil)
        #expect(NotchActivity.quotaGlance(quota(86)).session == nil)
    }
}
