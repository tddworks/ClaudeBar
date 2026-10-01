import Foundation

/// Decides what — if anything — the notch shows right now.
///
/// Pure: monitor state in, one activity or nothing out. No AppKit, no clock of
/// its own, no I/O. Every rule about what wins the notch lives here so the
/// window and its views stay presentation-only, and so the rules are testable
/// as plain state assertions.
public struct NotchActivityResolver: Sendable {
    /// How long a finished session keeps the notch before it retracts.
    public static let defaultFinishedDisplayDuration: TimeInterval = 4

    private let finishedDisplayDuration: TimeInterval

    public init(finishedDisplayDuration: TimeInterval = NotchActivityResolver.defaultFinishedDisplayDuration) {
        self.finishedDisplayDuration = finishedDisplayDuration
    }

    /// Resolves the single activity worth showing.
    ///
    /// - Parameters:
    ///   - sessions: Live and recently finished sessions. Callers filter out
    ///     ClaudeBar's own probe runs before this point.
    ///   - quotas: Every provider quota currently known.
    ///   - headlineQuota: The quota the user chose to watch, shown whenever
    ///     nothing louder is happening. Nil before the first probe returns.
    ///   - now: The reference time, so the "done" flash can expire deterministically.
    /// - Returns: The winning activity, or nil when the notch should stay hidden.
    public func resolve(
        sessions: [ClaudeSession],
        quotas: [UsageQuota],
        headlineQuota: UsageQuota?,
        now: Date
    ) -> NotchActivity? {
        var candidates = sessions.compactMap { activity(for: $0, now: now) }

        if let quota = mostDepletedQuotaNeedingAttention(in: quotas) {
            candidates.append(.quotaThreshold(quota))
        }

        if let headlineQuota {
            candidates.append(.quotaGlance(headlineQuota))
        }

        guard let topSeverity = candidates.map(\.severity).max() else { return nil }

        // Among equally severe activities the one that has been waiting longest
        // wins — a session blocked ten minutes ago needs the user more than one
        // blocked ten seconds ago.
        return candidates
            .filter { $0.severity == topSeverity }
            .min { lhs, rhs in
                guard let left = lhs.session, let right = rhs.session else { return false }
                return left.startedAt < right.startedAt
            }
    }

    // MARK: - Private

    private func activity(for session: ClaudeSession, now: Date) -> NotchActivity? {
        switch session.phase {
        case .awaitingInput:
            .awaitingInput(session)
        case .subagentsWorking:
            .agentsWorking(session)
        case .active:
            .working(session)
        case .stopped, .ended:
            finishedActivity(for: session, now: now)
        }
    }

    private func finishedActivity(for session: ClaudeSession, now: Date) -> NotchActivity? {
        guard let finishedAt = session.finishedAt,
              now.timeIntervalSince(finishedAt) < finishedDisplayDuration
        else { return nil }
        return .finished(session)
    }

    /// Only `.critical` and `.depleted` quotas are worth taking over the notch.
    /// `.warning` is real but not urgent, and a notch that lights up at half a
    /// tank stops meaning anything.
    private func mostDepletedQuotaNeedingAttention(in quotas: [UsageQuota]) -> UsageQuota? {
        quotas
            .filter { quota in
                switch QuotaStatus.from(percentRemaining: quota.percentRemaining) {
                case .critical, .depleted: true
                case .healthy, .warning: false
                }
            }
            .min { $0.percentRemaining < $1.percentRemaining }
    }
}
