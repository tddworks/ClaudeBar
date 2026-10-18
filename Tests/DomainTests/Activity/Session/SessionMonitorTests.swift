import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
@MainActor
struct SessionMonitorTests {
    private func makeEvent(
        sessionId: String = "test-session",
        eventName: SessionEvent.EventName,
        cwd: String = "/tmp/project",
        receivedAt: Date = Date(),
        message: String? = nil,
        processId: Int? = nil,
        titles: TranscriptTitles? = nil
    ) -> SessionEvent {
        SessionEvent(
            sessionId: sessionId,
            eventName: eventName,
            cwd: cwd,
            receivedAt: receivedAt,
            message: message,
            processId: processId,
            titles: titles
        )
    }

    /// A Mac on which only the given Claude Code processes are still running.
    private func processes(running alive: Set<Int>) -> MockProcessLiveness {
        let liveness = MockProcessLiveness()
        given(liveness).isRunning(processId: .any).willProduce { alive.contains($0) }
        return liveness
    }

    private func session(_ id: String, in monitor: SessionMonitor) -> ClaudeSession? {
        monitor.sessions.first { $0.id == id }
    }

    // MARK: - Session Lifecycle

    @Test
    func `should show no session and no recent sessions before Claude Code starts one`() {
        let monitor = SessionMonitor()

        #expect(monitor.activeSession == nil)
        #expect(monitor.hasActiveSession == false)
        #expect(monitor.sessions.isEmpty)
        #expect(monitor.recentSessions.isEmpty)
    }

    @Test
    func `should show a session in its folder, idle until the first prompt, when Claude Code starts one`() {
        // A session that has just opened sits at its prompt; it is not working,
        // and it has not finished anything either, so the notch has nothing to flash.
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))

        #expect(monitor.activeSession != nil)
        #expect(monitor.activeSession?.id == "test-session")
        #expect(monitor.activeSession?.cwd == "/tmp/project")
        #expect(monitor.activeSession?.phase == .stopped)
        #expect(monitor.activeSession?.finishedAt == nil)
        #expect(monitor.hasActiveSession == true)
    }

    @Test
    func `should show the session working once the person sends the first prompt`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))

        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        #expect(monitor.activeSession?.phase == .active)
    }

    @Test
    func `should keep a working session working when Claude Code starts it again mid-turn, as on compaction`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        monitor.processEvent(makeEvent(eventName: .sessionStart))

        #expect(monitor.activeSession?.phase == .active)
    }

    @Test
    func `should move the session to recent sessions as ended when Claude Code ends it`() {
        let monitor = SessionMonitor()
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(60)

        monitor.processEvent(makeEvent(eventName: .sessionStart, receivedAt: startDate))
        monitor.processEvent(makeEvent(eventName: .sessionEnd, receivedAt: endDate))

        #expect(monitor.activeSession == nil)
        #expect(monitor.hasActiveSession == false)
        #expect(monitor.recentSessions.count == 1)
        #expect(monitor.recentSessions.first?.id == "test-session")
        #expect(monitor.recentSessions.first?.phase == .ended)
    }

    @Test
    func `should keep the running session when another session ends`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionEnd))

        #expect(monitor.activeSession?.id == "session-1")
        #expect(monitor.recentSessions.isEmpty)
    }

    // MARK: - Several Sessions

    @Test
    func `should keep the first session running when a second one starts`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionStart))

        #expect(monitor.sessions.map(\.id) == ["session-1", "session-2"])
        #expect(monitor.recentSessions.isEmpty)
    }

    @Test
    func `should pick up a session that was running before ClaudeBar started from its next event`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "older", eventName: .userPromptSubmit, cwd: "/tmp/older"))

        #expect(monitor.activeSession?.id == "older")
        #expect(monitor.activeSession?.cwd == "/tmp/older")
        #expect(monitor.activeSession?.phase == .active)
    }

    @Test
    func `should pick up a session as done when its first event does not show a turn underway`() {
        // A SubagentStop or TaskCompleted says nothing about whether the turn
        // is still going; claiming "Working" would stick until the next prompt.
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "late-agent", eventName: .subagentStop))
        monitor.processEvent(makeEvent(sessionId: "late-task", eventName: .taskCompleted))
        monitor.processEvent(makeEvent(sessionId: "prompted", eventName: .userPromptSubmit))
        monitor.processEvent(makeEvent(sessionId: "agent", eventName: .subagentStart))

        #expect(session("late-agent", in: monitor)?.phase == .stopped)
        #expect(session("late-task", in: monitor)?.phase == .stopped)
        #expect(session("late-task", in: monitor)?.completedTaskCount == 1)
        #expect(session("prompted", in: monitor)?.phase == .active)
        #expect(session("agent", in: monitor)?.phase == .subagentsWorking)
    }

    @Test
    func `should keep following an earlier session after a newer one starts`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .stop))

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .subagentStart))

        #expect(monitor.activeSession?.id == "session-1")
        #expect(monitor.activeSession?.phase == .subagentsWorking)
    }

    @Test
    func `should show the session that needs the person ahead of ones that are working`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "blocked", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "blocked", eventName: .notification))

        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .subagentStart))

        #expect(monitor.activeSession?.id == "blocked")
    }

    @Test
    func `should show a working session ahead of a stopped one that spoke last`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .userPromptSubmit))
        monitor.processEvent(makeEvent(sessionId: "idle", eventName: .sessionStart))

        monitor.processEvent(makeEvent(sessionId: "idle", eventName: .stop))

        #expect(monitor.activeSession?.id == "busy")
    }

    @Test
    func `should show the session heard from last when several are in the same phase`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart, receivedAt: start))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionStart, receivedAt: start.addingTimeInterval(1)))

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .userPromptSubmit, receivedAt: start.addingTimeInterval(2)))

        #expect(monitor.activeSession?.id == "session-1")
    }

    @Test
    func `should keep the other sessions running when one ends`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionStart))

        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionEnd))

        #expect(monitor.activeSession?.id == "session-1")
        #expect(monitor.recentSessions.map(\.id) == ["session-2"])
    }

    @Test
    func `should keep a session's progress when Claude Code starts it again`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .taskCompleted))

        monitor.processEvent(makeEvent(eventName: .sessionStart))

        #expect(monitor.sessions.count == 1)
        #expect(monitor.activeSession?.completedTaskCount == 1)
        #expect(monitor.recentSessions.isEmpty)
    }

    @Test
    func `should rank sessions by how much they need the person, then by who spoke last`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "idle", eventName: .sessionStart, receivedAt: start))
        monitor.processEvent(makeEvent(sessionId: "idle", eventName: .stop, receivedAt: start.addingTimeInterval(1)))
        monitor.processEvent(makeEvent(sessionId: "active-old", eventName: .sessionStart, receivedAt: start.addingTimeInterval(2)))
        monitor.processEvent(makeEvent(sessionId: "agents", eventName: .sessionStart, receivedAt: start.addingTimeInterval(3)))
        monitor.processEvent(makeEvent(sessionId: "agents", eventName: .subagentStart, receivedAt: start.addingTimeInterval(4)))
        monitor.processEvent(makeEvent(sessionId: "blocked", eventName: .sessionStart, receivedAt: start.addingTimeInterval(5)))
        monitor.processEvent(makeEvent(sessionId: "blocked", eventName: .notification, receivedAt: start.addingTimeInterval(6)))
        monitor.processEvent(makeEvent(sessionId: "active-new", eventName: .sessionStart, receivedAt: start.addingTimeInterval(7)))

        #expect(monitor.sessionsByProminence.map(\.id) == ["blocked", "agents", "active-new", "active-old", "idle"])
        #expect(monitor.sessions.map(\.id) == ["idle", "active-old", "agents", "blocked", "active-new"])
    }

    // MARK: - What the Claude Code card shows

    @Test
    func `should list only the sessions that aren't done, most pressing first`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "idle", eventName: .sessionStart, receivedAt: start))
        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .userPromptSubmit, receivedAt: start.addingTimeInterval(1)))
        monitor.processEvent(makeEvent(sessionId: "blocked", eventName: .notification, receivedAt: start.addingTimeInterval(2)))
        monitor.processEvent(makeEvent(sessionId: "finished", eventName: .stop, receivedAt: start.addingTimeInterval(3)))

        #expect(monitor.sessionsInPlay.map(\.id) == ["blocked", "busy"])
    }

    @Test
    func `should count each kind of session: needing you, working, done`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "blocked", eventName: .notification))
        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .userPromptSubmit))
        monitor.processEvent(makeEvent(sessionId: "idle-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "idle-2", eventName: .stop))

        #expect(monitor.tally == SessionTally(needsYou: 1, working: 1, done: 2))
    }

    @Test
    func `should count sessions with agents as working`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "agents", eventName: .subagentStart))
        monitor.processEvent(makeEvent(sessionId: "busy", eventName: .userPromptSubmit))

        #expect(monitor.tally == SessionTally(needsYou: 0, working: 2, done: 0))
    }

    @Test
    func `should fold done sessions in the same repo into one, with the latest finish`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "a", eventName: .stop, cwd: "/code/claudebar", receivedAt: start))
        monitor.processEvent(makeEvent(sessionId: "b", eventName: .stop, cwd: "/code/claudebar", receivedAt: start.addingTimeInterval(60)))
        monitor.processEvent(makeEvent(sessionId: "c", eventName: .userPromptSubmit, cwd: "/code/claudebar", receivedAt: start.addingTimeInterval(90)))

        #expect(monitor.doneByRepo == [DoneRepo(repoName: "claudebar", count: 2, lastFinishedAt: start.addingTimeInterval(60))])
    }

    @Test
    func `should put the repo that finished last first`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "a", eventName: .stop, cwd: "/code/catalog", receivedAt: start))
        monitor.processEvent(makeEvent(sessionId: "b", eventName: .stop, cwd: "/code/claudebar", receivedAt: start.addingTimeInterval(60)))

        #expect(monitor.doneByRepo.map(\.repoName) == ["claudebar", "catalog"])
    }

    @Test
    func `should date a done session that never ran a turn from when it started`() {
        let monitor = SessionMonitor()
        let opened = Date()
        monitor.processEvent(makeEvent(sessionId: "fresh", eventName: .sessionStart, cwd: "/code/tinyshop", receivedAt: opened))

        #expect(monitor.doneByRepo == [DoneRepo(repoName: "tinyshop", count: 1, lastFinishedAt: opened)])
    }

    @Test
    func `should show a done session's title when it is alone in its repo`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "a", eventName: .stop, cwd: "/code/tinyshop", receivedAt: start,
                                       titles: TranscriptTitles(named: "Empty cart", generated: nil)))

        #expect(monitor.doneByRepo.first?.title == "Empty cart")
    }

    @Test
    func `should show no title for a repo's folded done sessions`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "a", eventName: .stop, cwd: "/code/claudebar", receivedAt: start,
                                       titles: TranscriptTitles(named: "Session names", generated: nil)))
        monitor.processEvent(makeEvent(sessionId: "b", eventName: .stop, cwd: "/code/claudebar", receivedAt: start,
                                       titles: TranscriptTitles(named: nil, generated: "Pull latest main")))

        #expect(monitor.doneByRepo.first?.count == 2)
        #expect(monitor.doneByRepo.first?.title == nil)
    }

    // MARK: - Titles

    @Test
    func `should title a session from its event`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .userPromptSubmit, titles: TranscriptTitles(named: nil, generated: "Pull latest main")))

        #expect(session("test-session", in: monitor)?.title == "Pull latest main")
    }

    @Test
    func `should keep a session's title when an event found none`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit, titles: TranscriptTitles(named: "Session names", generated: nil)))

        monitor.processEvent(makeEvent(eventName: .stop))

        #expect(session("test-session", in: monitor)?.title == "Session names")
    }

    @Test
    func `should title an ended session from its last event`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))

        monitor.processEvent(makeEvent(eventName: .sessionEnd, titles: TranscriptTitles(named: "Session names", generated: nil)))

        #expect(monitor.recentSessions.first?.title == "Session names")
    }

    // MARK: - Sessions whose Claude Code process is gone

    @Test
    func `should end a session whose Claude Code process is gone, keeping the ones still running`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(sessionId: "alive", eventName: .sessionStart, receivedAt: start, processId: 100))
        monitor.processEvent(makeEvent(sessionId: "killed", eventName: .sessionStart, receivedAt: start, processId: 200))

        let now = start.addingTimeInterval(60)
        monitor.endSessionsWhoseProcessIsGone(according: processes(running: [100]), at: now)

        #expect(monitor.sessions.map(\.id) == ["alive"])
        #expect(monitor.recentSessions.map(\.id) == ["killed"])
        #expect(monitor.recentSessions.first?.phase == .ended)
        #expect(monitor.recentSessions.first?.endedAt == now)
    }

    @Test
    func `should keep a session that never said which process it runs in`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(sessionId: "unknown-pid", eventName: .sessionStart))

        monitor.endSessionsWhoseProcessIsGone(according: processes(running: []), at: Date())

        #expect(monitor.sessions.map(\.id) == ["unknown-pid"])
    }

    @Test
    func `should learn a session's process from a later event when the first one had none`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit, processId: 300))

        monitor.endSessionsWhoseProcessIsGone(according: processes(running: []), at: Date())

        #expect(monitor.sessions.isEmpty)
        #expect(monitor.recentSessions.first?.processId == 300)
    }

    // MARK: - Task Tracking

    @Test
    func `should count each task Claude Code finishes in the session`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .taskCompleted))
        monitor.processEvent(makeEvent(eventName: .taskCompleted))

        #expect(monitor.activeSession?.completedTaskCount == 2)
    }

    @Test
    func `should count a task for the session that finished it, not the others`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "other", eventName: .taskCompleted))

        #expect(session("session-1", in: monitor)?.completedTaskCount == 0)
        #expect(session("other", in: monitor)?.completedTaskCount == 1)
    }

    // MARK: - Subagent Tracking

    @Test
    func `should show agents working when a subagent starts in the session`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))

        #expect(monitor.activeSession?.phase == .subagentsWorking)
        #expect(monitor.activeSession?.activeSubagentCount == 1)
    }

    @Test
    func `should go back to active when the session's last subagent stops`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .subagentStop))

        #expect(monitor.activeSession?.phase == .active)
        #expect(monitor.activeSession?.activeSubagentCount == 0)
    }

    @Test
    func `should keep two agents working when one of three subagents stops`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .subagentStop))

        #expect(monitor.activeSession?.activeSubagentCount == 2)
        #expect(monitor.activeSession?.phase == .subagentsWorking)
    }

    // MARK: - Stop

    @Test
    func `should show the session done when its turn ends in an error, as after the Mac slept`() {
        let monitor = SessionMonitor()
        let start = Date()
        monitor.processEvent(makeEvent(eventName: .sessionStart, receivedAt: start))
        monitor.processEvent(makeEvent(eventName: .subagentStart, receivedAt: start))

        let failedAt = start.addingTimeInterval(3600)
        monitor.processEvent(makeEvent(eventName: .stopFailure, receivedAt: failedAt, message: "Connection error"))

        #expect(monitor.activeSession?.phase == .stopped)
        #expect(monitor.activeSession?.activeSubagentCount == 0)
        #expect(monitor.activeSession?.stoppedAt == failedAt)
    }

    @Test
    func `should show the session stopped with no agents when Claude stops`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .stop))

        #expect(monitor.activeSession?.phase == .stopped)
        #expect(monitor.activeSession?.activeSubagentCount == 0)
    }

    @Test
    func `should stop only the session that stopped`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .userPromptSubmit))
        monitor.processEvent(makeEvent(sessionId: "other", eventName: .stop))

        #expect(session("session-1", in: monitor)?.phase == .active)
        #expect(session("other", in: monitor)?.phase == .stopped)
    }

    @Test
    func `should bring a stopped session back to active when the person sends a prompt`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .stop))
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        #expect(monitor.activeSession?.phase == .active)
    }

    @Test
    func `should keep the session stopped when the person prompts another session`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .stop))
        monitor.processEvent(makeEvent(sessionId: "other", eventName: .userPromptSubmit))

        #expect(session("session-1", in: monitor)?.phase == .stopped)
    }

    // MARK: - Recent Sessions

    @Test
    func `should list the most recent session first`() {
        let monitor = SessionMonitor()
        let now = Date()

        monitor.processEvent(makeEvent(sessionId: "s1", eventName: .sessionStart, receivedAt: now))
        monitor.processEvent(makeEvent(sessionId: "s1", eventName: .sessionEnd, receivedAt: now.addingTimeInterval(10)))

        monitor.processEvent(makeEvent(sessionId: "s2", eventName: .sessionStart, receivedAt: now.addingTimeInterval(20)))
        monitor.processEvent(makeEvent(sessionId: "s2", eventName: .sessionEnd, receivedAt: now.addingTimeInterval(30)))

        #expect(monitor.recentSessions.count == 2)
        #expect(monitor.recentSessions[0].id == "s2")
        #expect(monitor.recentSessions[1].id == "s1")
    }

    @Test
    func `should keep only the latest sessions up to the limit`() {
        let monitor = SessionMonitor(maxRecentSessions: 3)
        let now = Date()

        for i in 1...5 {
            let time = now.addingTimeInterval(Double(i * 10))
            monitor.processEvent(makeEvent(sessionId: "s\(i)", eventName: .sessionStart, receivedAt: time))
            monitor.processEvent(makeEvent(sessionId: "s\(i)", eventName: .sessionEnd, receivedAt: time.addingTimeInterval(5)))
        }

        #expect(monitor.recentSessions.count == 3)
        #expect(monitor.recentSessions[0].id == "s5")
        #expect(monitor.recentSessions[1].id == "s4")
        #expect(monitor.recentSessions[2].id == "s3")
    }

    // MARK: - Complex Scenarios

    @Test
    func `should follow a session through subagents and tasks and keep its task count once it ends`() {
        let monitor = SessionMonitor()

        // Start session and send the first prompt
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))
        #expect(monitor.activeSession?.phase == .active)

        // Work with subagents
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        #expect(monitor.activeSession?.phase == .subagentsWorking)

        // Task completed while subagent running
        monitor.processEvent(makeEvent(eventName: .taskCompleted))
        #expect(monitor.activeSession?.completedTaskCount == 1)

        // Subagent finishes
        monitor.processEvent(makeEvent(eventName: .subagentStop))
        #expect(monitor.activeSession?.phase == .active)

        // More tasks
        monitor.processEvent(makeEvent(eventName: .taskCompleted))
        #expect(monitor.activeSession?.completedTaskCount == 2)

        // Session ends
        monitor.processEvent(makeEvent(eventName: .sessionEnd))
        #expect(monitor.activeSession == nil)
        #expect(monitor.recentSessions.count == 1)
        #expect(monitor.recentSessions.first?.completedTaskCount == 2)
    }

    // MARK: - Permission Prompts

    @Test
    func `should show the session needs the person, with the prompt, when Claude Code asks for permission`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))

        monitor.processEvent(makeEvent(eventName: .notification, message: "Claude needs your permission to use Bash"))

        #expect(monitor.activeSession?.phase == .awaitingInput)
        #expect(monitor.activeSession?.pendingPrompt == "Claude needs your permission to use Bash")
    }

    @Test
    func `should keep the session active when another session asks for permission`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        monitor.processEvent(makeEvent(sessionId: "other", eventName: .notification, message: "blocked"))

        #expect(session("test-session", in: monitor)?.phase == .active)
        #expect(session("test-session", in: monitor)?.pendingPrompt == nil)
    }

    @Test
    func `should drop the prompt and go back to active when the person answers the session`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .notification, message: "blocked"))

        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        #expect(monitor.activeSession?.phase == .active)
        #expect(monitor.activeSession?.pendingPrompt == nil)
    }
}
