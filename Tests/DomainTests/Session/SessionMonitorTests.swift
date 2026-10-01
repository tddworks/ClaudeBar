import Testing
import Foundation
@testable import Domain

@Suite
@MainActor
struct SessionMonitorTests {
    private func makeEvent(
        sessionId: String = "test-session",
        eventName: SessionEvent.EventName,
        cwd: String = "/tmp/project",
        receivedAt: Date = Date(),
        message: String? = nil
    ) -> SessionEvent {
        SessionEvent(
            sessionId: sessionId,
            eventName: eventName,
            cwd: cwd,
            receivedAt: receivedAt,
            message: message
        )
    }

    // MARK: - Session Lifecycle

    @Test
    func `starts with no active session`() {
        let monitor = SessionMonitor()

        #expect(monitor.activeSession == nil)
        #expect(monitor.hasActiveSession == false)
        #expect(monitor.recentSessions.isEmpty)
    }

    @Test
    func `SessionStart creates active session`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))

        #expect(monitor.activeSession != nil)
        #expect(monitor.activeSession?.id == "test-session")
        #expect(monitor.activeSession?.cwd == "/tmp/project")
        #expect(monitor.activeSession?.phase == .active)
        #expect(monitor.hasActiveSession == true)
    }

    @Test
    func `SessionEnd moves session to recent and clears active`() {
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
    func `SessionEnd for different session ID is ignored`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionEnd))

        #expect(monitor.activeSession?.id == "session-1")
        #expect(monitor.recentSessions.isEmpty)
    }

    @Test
    func `new SessionStart ends previous session`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-2", eventName: .sessionStart))

        #expect(monitor.activeSession?.id == "session-2")
        #expect(monitor.recentSessions.count == 1)
        #expect(monitor.recentSessions.first?.id == "session-1")
    }

    // MARK: - Task Tracking

    @Test
    func `TaskCompleted increments task count`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .taskCompleted))
        monitor.processEvent(makeEvent(eventName: .taskCompleted))

        #expect(monitor.activeSession?.completedTaskCount == 2)
    }

    @Test
    func `TaskCompleted for wrong session ID is ignored`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "other", eventName: .taskCompleted))

        #expect(monitor.activeSession?.completedTaskCount == 0)
    }

    @Test
    func `TaskCompleted without active session is ignored`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .taskCompleted))

        #expect(monitor.activeSession == nil)
    }

    // MARK: - Subagent Tracking

    @Test
    func `SubagentStart changes phase to subagentsWorking`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))

        #expect(monitor.activeSession?.phase == .subagentsWorking)
        #expect(monitor.activeSession?.activeSubagentCount == 1)
    }

    @Test
    func `SubagentStop returns to active when no subagents remain`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .subagentStop))

        #expect(monitor.activeSession?.phase == .active)
        #expect(monitor.activeSession?.activeSubagentCount == 0)
    }

    @Test
    func `multiple subagents tracked correctly`() {
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
    func `Stop sets phase to stopped`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .subagentStart))
        monitor.processEvent(makeEvent(eventName: .stop))

        #expect(monitor.activeSession?.phase == .stopped)
        #expect(monitor.activeSession?.activeSubagentCount == 0)
    }

    @Test
    func `Stop for wrong session is ignored`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "other", eventName: .stop))

        #expect(monitor.activeSession?.phase == .active)
    }

    @Test
    func `UserPromptSubmit revives a stopped session to active`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .stop))
        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        #expect(monitor.activeSession?.phase == .active)
    }

    @Test
    func `UserPromptSubmit for wrong session is ignored`() {
        let monitor = SessionMonitor()

        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .sessionStart))
        monitor.processEvent(makeEvent(sessionId: "session-1", eventName: .stop))
        monitor.processEvent(makeEvent(sessionId: "other", eventName: .userPromptSubmit))

        #expect(monitor.activeSession?.phase == .stopped)
    }

    // MARK: - Recent Sessions

    @Test
    func `recent sessions are ordered most recent first`() {
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
    func `recent sessions are capped at max`() {
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
    func `full session lifecycle with tasks and subagents`() {
        let monitor = SessionMonitor()

        // Start session
        monitor.processEvent(makeEvent(eventName: .sessionStart))
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
    func `Notification moves the active session to awaitingInput`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))

        monitor.processEvent(makeEvent(eventName: .notification, message: "Claude needs your permission to use Bash"))

        #expect(monitor.activeSession?.phase == .awaitingInput)
        #expect(monitor.activeSession?.pendingPrompt == "Claude needs your permission to use Bash")
    }

    @Test
    func `Notification is ignored when it belongs to another session`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))

        monitor.processEvent(makeEvent(sessionId: "other", eventName: .notification, message: "blocked"))

        #expect(monitor.activeSession?.phase == .active)
        #expect(monitor.activeSession?.pendingPrompt == nil)
    }

    @Test
    func `UserPromptSubmit releases a session waiting on input`() {
        let monitor = SessionMonitor()
        monitor.processEvent(makeEvent(eventName: .sessionStart))
        monitor.processEvent(makeEvent(eventName: .notification, message: "blocked"))

        monitor.processEvent(makeEvent(eventName: .userPromptSubmit))

        #expect(monitor.activeSession?.phase == .active)
        #expect(monitor.activeSession?.pendingPrompt == nil)
    }
}
