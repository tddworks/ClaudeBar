import Foundation

/// A single thing the notch can say.
///
/// The notch is one strip of glass with several independent sources competing
/// for it — running sessions, permission prompts, quota thresholds. Modelling
/// each as a case lets `NotchActivityResolver` pick a winner without any view
/// knowing the rules.
///
/// Ordering is by how loudly the activity demands attention, so two activities
/// of the same kind are order-equivalent without being equal.
public enum NotchActivity: Sendable, Equatable {
    /// Nothing is happening, so the notch does the job ClaudeBar exists for:
    /// shows how much of the quota the user chose to watch is left.
    ///
    /// This is the resting state, not an absence of one. A notch that goes
    /// blank between sessions has no reason to be on screen at all.
    case quotaGlance(UsageQuota)

    /// Claude Code is working on a turn.
    case working(ClaudeSession)

    /// Claude Code has fanned subagents out.
    case agentsWorking(ClaudeSession)

    /// A provider is at or past the point where the user should know.
    case quotaThreshold(UsageQuota)

    /// A turn or session just finished. Transient — see
    /// `NotchActivityResolver.finishedDisplayDuration`.
    case finished(ClaudeSession)

    /// Claude Code is blocked waiting on the user. Outranks everything, and
    /// never expires on its own: only the user can clear it.
    case awaitingInput(ClaudeSession)

    /// The session behind this activity, for the activities that have one.
    public var session: ClaudeSession? {
        switch self {
        case .working(let session),
             .agentsWorking(let session),
             .finished(let session),
             .awaitingInput(let session):
            session
        case .quotaThreshold, .quotaGlance:
            nil
        }
    }

    /// The quota behind this activity, for the activities that have one.
    public var quota: UsageQuota? {
        switch self {
        case .quotaThreshold(let quota), .quotaGlance(let quota): quota
        default: nil
        }
    }

    /// How loudly this activity demands attention (higher wins).
    ///
    /// The ordering encodes two product rules: a human being blocked beats
    /// anything a machine is doing, and a "done" flash briefly interrupts
    /// ambient state without ever masking a blocked session.
    var severity: Int {
        switch self {
        case .quotaGlance: 0
        case .working: 1
        case .agentsWorking: 2
        case .quotaThreshold: 3
        case .finished: 4
        case .awaitingInput: 5
        }
    }
}

extension NotchActivity: Comparable {
    public static func < (lhs: NotchActivity, rhs: NotchActivity) -> Bool {
        lhs.severity < rhs.severity
    }
}
