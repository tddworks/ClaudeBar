import Quotas
import DataSources
import Providers
import Foundation
import Observation

/// Monitors Claude Code sessions by processing hook events.
/// Single source of truth for session state, similar to QuotaMonitor for providers.
/// Isolated to @MainActor since it's consumed by SwiftUI views.
///
/// Several sessions can run at once (one per terminal), and each is tracked on
/// its own. A session is picked up from whichever of its events arrives first,
/// not only `SessionStart`: one that was already running when ClaudeBar
/// launched sent its `SessionStart` before anything was listening.
@MainActor
@Observable
public final class SessionMonitor {
    /// Every session that is still running, in the order they were first seen.
    public private(set) var sessions: [ClaudeSession] = []

    /// Recently completed sessions (most recent first)
    public private(set) var recentSessions: [ClaudeSession] = []

    /// When each running session last sent an event, by session ID.
    private var lastEventAt: [String: Date] = [:]

    /// Maximum number of recent sessions to keep
    private let maxRecentSessions: Int

    public init(maxRecentSessions: Int = 10) {
        self.maxRecentSessions = maxRecentSessions
    }

    // MARK: - Event Processing

    /// Processes a session event and updates state accordingly.
    public func processEvent(_ event: SessionEvent) {
        if event.eventName == .sessionEnd {
            if let titles = event.titles, let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
                sessions[index].titled(titles)
            }
            endSession(event.sessionId, at: event.receivedAt)
            return
        }

        let index = indexOfSession(for: event)
        if let titles = event.titles {
            sessions[index].titled(titles)
        }
        lastEventAt[event.sessionId] = event.receivedAt
        if let processId = event.processId, sessions[index].processId == nil {
            sessions[index].runs(inProcess: processId)
        }

        switch event.eventName {
        case .sessionStart:
            // A new session sits idle at its prompt until the first prompt; one
            // already known is being resumed or compacted and keeps its phase
            // and progress — compaction happens mid-turn.
            break
        case .sessionEnd:
            break
        case .taskCompleted:
            sessions[index].taskCompleted()
        case .subagentStart:
            sessions[index].subagentStarted()
        case .subagentStop:
            sessions[index].subagentStopped()
        case .stop, .stopFailure:
            sessions[index].stop(at: event.receivedAt)
        case .userPromptSubmit:
            sessions[index].resume()
        case .notification:
            sessions[index].awaitInput(event.message, at: event.receivedAt)
        }
    }

    /// Ends every session whose Claude Code process no longer exists: it was
    /// killed without a `SessionEnd`, so nothing else will ever end it. A
    /// session that never said which process it runs in is left alone.
    public func endSessionsWhoseProcessIsGone(according liveness: ProcessLiveness, at date: Date) {
        let gone = sessions.filter { session in
            guard let processId = session.processId else { return false }
            return !liveness.isRunning(processId: processId)
        }
        for session in gone {
            endSession(session.id, at: date)
        }
    }

    // MARK: - Queries

    /// Every running session, the one that most needs the user's eye first:
    /// a blocked session outranks one with agents working, which outranks one
    /// working alone, which outranks one that has stopped. Among equals, the
    /// one heard from last comes first. This is the order a list shows them in.
    public var sessionsByProminence: [ClaudeSession] {
        sessions.sorted { lhs, rhs in
            let left = Self.prominence(of: lhs.phase)
            let right = Self.prominence(of: rhs.phase)
            guard left == right else { return left > right }
            return lastHeard(from: lhs) > lastHeard(from: rhs)
        }
    }

    /// The one session to show where there is room for a single status (the
    /// menu bar glyph): the first by prominence. nil when no session is running.
    public var activeSession: ClaudeSession? {
        sessionsByProminence.first
    }

    /// Whether there's an active Claude Code session
    public var hasActiveSession: Bool {
        !sessions.isEmpty
    }

    /// The sessions still in play, every one that isn't Done, most pressing
    /// first: the rows of the Claude Code card.
    public var sessionsInPlay: [ClaudeSession] {
        sessionsByProminence.filter { $0.phase != .stopped }
    }

    /// How many sessions need the person, are working, or are done.
    public var tally: SessionTally {
        SessionTally(
            needsYou: sessions.count { $0.phase == .awaitingInput },
            working: sessions.count { $0.phase == .active || $0.phase == .subagentsWorking },
            done: sessions.count { $0.phase == .stopped }
        )
    }

    /// The Done sessions, one entry per repo, the repo that finished last first.
    public var doneByRepo: [DoneRepo] {
        let done = sessions.filter { $0.phase == .stopped }
        return Dictionary(grouping: done, by: \.repoName)
            .map { repoName, sessions in
                DoneRepo(
                    repoName: repoName,
                    count: sessions.count,
                    lastFinishedAt: sessions.map { $0.finishedAt ?? $0.startedAt }.max() ?? .distantPast,
                    title: sessions.count == 1 ? sessions[0].title : nil
                )
            }
            .sorted { lhs, rhs in
                lhs.lastFinishedAt == rhs.lastFinishedAt ? lhs.repoName < rhs.repoName : lhs.lastFinishedAt > rhs.lastFinishedAt
            }
    }

    // MARK: - Private

    private func lastHeard(from session: ClaudeSession) -> Date {
        lastEventAt[session.id] ?? session.startedAt
    }

    private static func prominence(of phase: ClaudeSession.Phase) -> Int {
        switch phase {
        case .awaitingInput: 3
        case .subagentsWorking: 2
        case .active: 1
        case .stopped, .ended: 0
        }
    }

    /// The position of the event's session, adding it first if this is the
    /// first event seen from it. A session that has just started sits idle at
    /// its prompt. One picked up mid-flight starts out stopped too unless the
    /// event itself shows a turn underway — a late `SubagentStop` or
    /// `TaskCompleted` says nothing about that, and claiming "Working" would
    /// stick until the next prompt — and its `startedAt` is when ClaudeBar
    /// first heard from it, not when it really began.
    private func indexOfSession(for event: SessionEvent) -> Int {
        if let index = sessions.firstIndex(where: { $0.id == event.sessionId }) {
            return index
        }
        var session = ClaudeSession(
            id: event.sessionId,
            cwd: event.cwd,
            startedAt: event.receivedAt,
            processId: event.processId,
            phase: event.eventName == .sessionStart ? .stopped : .active
        )
        switch event.eventName {
        case .sessionStart, .userPromptSubmit, .subagentStart, .notification:
            break
        case .subagentStop, .taskCompleted, .stop, .stopFailure, .sessionEnd:
            session.stop(at: event.receivedAt)
        }
        sessions.append(session)
        return sessions.count - 1
    }

    private func endSession(_ id: String, at date: Date) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions.remove(at: index)
        lastEventAt.removeValue(forKey: id)
        session.end(at: date)
        recentSessions.insert(session, at: 0)
        if recentSessions.count > maxRecentSessions {
            recentSessions = Array(recentSessions.prefix(maxRecentSessions))
        }
    }
}
