import Foundation
import Combine

/// Monitors Claude Code sessions by processing hook events.
/// Single source of truth for session state, similar to QuotaMonitor for providers.
/// Isolated to @MainActor since it's consumed by SwiftUI views.
public final class SessionMonitor: ObservableObject, @unchecked Sendable {
    public let objectWillChange = ObservableObjectPublisher()

    /// The currently active session (nil if no session is running)
    @Published public private(set) var activeSession: ClaudeSession?

    /// Recently completed sessions (most recent first)
    @Published public private(set) var recentSessions: [ClaudeSession] = []

    /// Maximum number of recent sessions to keep
    private let maxRecentSessions: Int

    public init(maxRecentSessions: Int = 10) {
        self.maxRecentSessions = maxRecentSessions
    }

    // MARK: - Event Processing

    /// Processes a session event and updates state accordingly.
    public func processEvent(_ event: SessionEvent) {
        switch event.eventName {
        case .sessionStart:
            handleSessionStart(event)
        case .sessionEnd:
            handleSessionEnd(event)
        case .taskCompleted:
            handleTaskCompleted(event)
        case .subagentStart:
            handleSubagentStart(event)
        case .subagentStop:
            handleSubagentStop(event)
        case .stop:
            handleStop(event)
        }
    }

    // MARK: - Queries

    /// Whether there's an active Claude Code session
    public var hasActiveSession: Bool {
        activeSession != nil
    }

    // MARK: - Private Handlers

    private func handleSessionStart(_ event: SessionEvent) {
        // End any existing session before starting a new one
        if activeSession != nil {
            endCurrentSession(at: event.receivedAt)
        }
        activeSession = ClaudeSession(
            id: event.sessionId,
            cwd: event.cwd,
            startedAt: event.receivedAt
        )
    }

    private func handleSessionEnd(_ event: SessionEvent) {
        guard activeSession?.id == event.sessionId else { return }
        endCurrentSession(at: event.receivedAt)
    }

    private func handleTaskCompleted(_ event: SessionEvent) {
        guard activeSession?.id == event.sessionId else { return }
        activeSession?.taskCompleted()
    }

    private func handleSubagentStart(_ event: SessionEvent) {
        guard activeSession?.id == event.sessionId else { return }
        activeSession?.subagentStarted()
    }

    private func handleSubagentStop(_ event: SessionEvent) {
        guard activeSession?.id == event.sessionId else { return }
        activeSession?.subagentStopped()
    }

    private func handleStop(_ event: SessionEvent) {
        guard activeSession?.id == event.sessionId else { return }
        activeSession?.stop()
    }

    private func endCurrentSession(at date: Date) {
        guard var session = activeSession else { return }
        session.end(at: date)
        recentSessions.insert(session, at: 0)
        if recentSessions.count > maxRecentSessions {
            recentSessions = Array(recentSessions.prefix(maxRecentSessions))
        }
        activeSession = nil
    }
}
