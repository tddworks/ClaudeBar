import Testing
import Foundation
@testable import Domain

@Suite
struct ClaudeSessionTests {
    @Test
    func `should be active with no agents or finished tasks when the session starts`() {
        let session = ClaudeSession(id: "test", cwd: "/tmp")

        #expect(session.phase == .active)
        #expect(session.activeSubagentCount == 0)
        #expect(session.completedTaskCount == 0)
        #expect(session.isActive == true)
        #expect(session.endedAt == nil)
    }

    @Test
    func `should be idle, with nothing finished, when opened at its prompt`() {
        let session = ClaudeSession(id: "test", cwd: "/tmp", phase: .stopped)

        #expect(session.phase == .stopped)
        #expect(session.finishedAt == nil)
        #expect(session.isActive == true)
        #expect(session.activeSubagentCount == 0)
        #expect(session.completedTaskCount == 0)
        #expect(session.isActive == true)
        #expect(session.endedAt == nil)
    }

    @Test
    func `should show agents working when a subagent starts`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()

        #expect(session.phase == .subagentsWorking)
        #expect(session.activeSubagentCount == 1)
    }

    @Test
    func `should count three agents working when three subagents start`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()
        session.subagentStarted()
        session.subagentStarted()

        #expect(session.activeSubagentCount == 3)
        #expect(session.phase == .subagentsWorking)
    }

    @Test
    func `should go back to active when the last subagent stops`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()
        session.subagentStopped()

        #expect(session.activeSubagentCount == 0)
        #expect(session.phase == .active)
    }

    @Test
    func `should keep showing agents working while a subagent is still running`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStarted()
        session.subagentStarted()
        session.subagentStopped()

        #expect(session.activeSubagentCount == 1)
        #expect(session.phase == .subagentsWorking)
    }

    @Test
    func `should count no agents, never fewer, when more subagents stop than started`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.subagentStopped()
        session.subagentStopped()

        #expect(session.activeSubagentCount == 0)
        #expect(session.phase == .active)
    }

    @Test
    func `should stay stopped when a subagent reports stopping after Claude stopped`() {
        // Claude Code reports a subagent's stop a moment after the turn's own
        // Stop; that must not make an idle session look like it is working.
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()
        let stoppedAt = Date()
        session.stop(at: stoppedAt)

        session.subagentStopped()

        #expect(session.phase == .stopped)
        #expect(session.stoppedAt == stoppedAt)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `should keep needing the person, with the prompt, when a subagent stops`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()
        session.awaitInput("Claude needs your permission to use Bash")

        session.subagentStopped()

        #expect(session.phase == .awaitingInput)
        #expect(session.pendingPrompt == "Claude needs your permission to use Bash")
    }

    @Test
    func `should count each finished task`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.taskCompleted()
        session.taskCompleted()
        session.taskCompleted()

        #expect(session.completedTaskCount == 3)
    }

    @Test
    func `should show the session stopped with no agents, yet not ended, when Claude stops`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()
        session.subagentStarted()

        session.stop()

        #expect(session.phase == .stopped)
        #expect(session.activeSubagentCount == 0)
        #expect(session.isActive == true) // stopped but not ended
    }

    @Test
    func `should show the session ended with its end time when it ends`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        let endDate = Date()

        session.end(at: endDate)

        #expect(session.phase == .ended)
        #expect(session.isActive == false)
        #expect(session.endedAt == endDate)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `should print a 45-second session as 45s`() {
        let start = Date()
        var session = ClaudeSession(id: "test", cwd: "/tmp", startedAt: start)
        session.end(at: start.addingTimeInterval(45))

        #expect(session.durationDescription == "45s")
    }

    @Test
    func `should print a session of just over two minutes as 2m 5s`() {
        let start = Date()
        var session = ClaudeSession(id: "test", cwd: "/tmp", startedAt: start)
        session.end(at: start.addingTimeInterval(125)) // 2m 5s

        #expect(session.durationDescription == "2m 5s")
    }

    @Test
    func `should print a session of just over an hour as 1h 1m`() {
        let start = Date()
        var session = ClaudeSession(id: "test", cwd: "/tmp", startedAt: start)
        session.end(at: start.addingTimeInterval(3660)) // 1h 1m

        #expect(session.durationDescription == "1h 1m")
    }

    @Test
    func `should be known by its id wherever it runs`() {
        let session1 = ClaudeSession(id: "abc", cwd: "/tmp")
        let session2 = ClaudeSession(id: "abc", cwd: "/other")

        #expect(session1.id == session2.id)
    }

    // MARK: - Phase Guards

    @Test
    func `should show agents working again when a subagent starts after Claude stopped`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.subagentStarted()

        #expect(session.phase == .subagentsWorking)
        #expect(session.activeSubagentCount == 1)
    }

    @Test
    func `should go back to active when the person resumes a stopped session`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.resume()

        #expect(session.phase == .active)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `should keep showing agents working when the session resumes with a subagent running`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()

        session.resume()

        #expect(session.phase == .subagentsWorking)
        #expect(session.activeSubagentCount == 1)
    }

    @Test
    func `should stay ended when an ended session is resumed`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.resume()

        #expect(session.phase == .ended)
    }

    @Test
    func `should stay ended with no agents when a subagent stops after the session ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.subagentStarted()
        session.end()

        session.subagentStopped()

        #expect(session.phase == .ended)
        #expect(session.activeSubagentCount == 0)
    }

    @Test
    func `should still count a task finished after Claude stopped`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.taskCompleted()

        #expect(session.completedTaskCount == 1)
    }

    @Test
    func `should not count a task finished after the session ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.taskCompleted()

        #expect(session.completedTaskCount == 0)
    }

    @Test
    func `should stay ended when Claude stops after the session ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.stop()

        #expect(session.phase == .ended)
    }


    // MARK: - Awaiting input

    @Test
    func `should show the session needs the person, with the prompt, when Claude asks for input`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.awaitInput("Bash · rm -rf build/")

        #expect(session.phase == .awaitingInput)
        #expect(session.pendingPrompt == "Bash · rm -rf build/")
    }

    @Test
    func `should stay ended with no prompt when Claude asks for input after the session ended`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.end()

        session.awaitInput("Bash · ls")

        #expect(session.phase == .ended)
        #expect(session.pendingPrompt == nil)
    }

    @Test
    func `should drop the prompt and go back to active when the person answers`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.awaitInput("Bash · ls")

        session.resume()

        #expect(session.phase == .active)
        #expect(session.pendingPrompt == nil)
    }

    @Test
    func `should drop the prompt and show agents working when a subagent starts`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.awaitInput("Bash · ls")

        session.subagentStarted()

        #expect(session.phase == .subagentsWorking)
        #expect(session.pendingPrompt == nil)
    }

    // MARK: - Finishing

    @Test
    func `should remember when Claude stopped as the time the session finished`() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        var session = ClaudeSession(id: "test", cwd: "/tmp")

        session.stop(at: when)

        #expect(session.stoppedAt == when)
        #expect(session.finishedAt == when)
    }

    @Test
    func `should have no finish time while the session runs`() {
        let session = ClaudeSession(id: "test", cwd: "/tmp")

        #expect(session.finishedAt == nil)
    }

    @Test
    func `should take the end time over the stop time as the time the session finished`() {
        let stopped = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = stopped.addingTimeInterval(30)
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop(at: stopped)

        session.end(at: ended)

        #expect(session.finishedAt == ended)
    }

    @Test
    func `should forget the stop time when a stopped session resumes`() {
        var session = ClaudeSession(id: "test", cwd: "/tmp")
        session.stop()

        session.resume()

        #expect(session.stoppedAt == nil)
        #expect(session.finishedAt == nil)
    }

    // MARK: - Identity

    @Test
    func `should name the session after the folder it runs in`() {
        let session = ClaudeSession(id: "test", cwd: "/Users/me/github/tddworks/claudebar")

        #expect(session.repoName == "claudebar")
    }

    @Test
    func `should name the session after its folder even when the path ends in a slash`() {
        let session = ClaudeSession(id: "test", cwd: "/Users/me/github/claudebar/")

        #expect(session.repoName == "claudebar")
    }

    @Test
    func `should print each phase with the notch's words: Working, Agents working, Needs you, Done or Ended`() {
        #expect(ClaudeSession.Phase.active.label == "Working")
        #expect(ClaudeSession.Phase.subagentsWorking.label == "Agents working")
        #expect(ClaudeSession.Phase.awaitingInput.label == "Needs you")
        #expect(ClaudeSession.Phase.stopped.label == "Done")
        #expect(ClaudeSession.Phase.ended.label == "Ended")
    }

    // MARK: - Title

    @Test
    func `should title a session by its name over Claude Code's`() {
        var session = ClaudeSession(id: "test", cwd: "/code/claudebar")

        session.titled(TranscriptTitles(named: "Session names", generated: "Pull latest main"))

        #expect(session.title == "Session names")
    }

    @Test
    func `should title a session by Claude Code's when it has no name`() {
        var session = ClaudeSession(id: "test", cwd: "/code/claudebar")

        session.titled(TranscriptTitles(named: nil, generated: "Pull latest main"))

        #expect(session.title == "Pull latest main")
    }

    @Test
    func `should have no title before either is known`() {
        let session = ClaudeSession(id: "test", cwd: "/code/claudebar")

        #expect(session.title == nil)
        #expect(session.repoAndTitle == "claudebar")
    }

    @Test
    func `should keep a name it was given when later titles found none`() {
        var session = ClaudeSession(id: "test", cwd: "/code/claudebar")
        session.titled(TranscriptTitles(named: "Session names", generated: nil))

        session.titled(TranscriptTitles(named: nil, generated: nil))

        #expect(session.title == "Session names")
    }

    @Test
    func `should name a session by its repo and title`() {
        var session = ClaudeSession(id: "test", cwd: "/code/claudebar")

        session.titled(TranscriptTitles(named: "Session names", generated: nil))

        #expect(session.repoAndTitle == "claudebar · Session names")
    }
}
