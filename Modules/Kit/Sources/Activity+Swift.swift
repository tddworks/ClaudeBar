import ClaudeBarKit
import Foundation

// Activity — Claude Code's sessions, the hooks, the notch — as Swift reads it.

extension Session: @retroactive @unchecked Sendable {}
extension SessionMonitor: @retroactive @unchecked Sendable {}
extension SessionTracking: @retroactive @unchecked Sendable {}
extension NotchActivity: @retroactive @unchecked Sendable {}
extension NotchActivityResolver: @retroactive @unchecked Sendable {}
extension HookInstaller: @retroactive @unchecked Sendable {}

extension Session: @retroactive Identifiable {
    public var startedAt: Date { Date(kernelSeconds: startedAtSeconds) }
    public var endedAt: Date? { endedAtSeconds.swift.map(Date.init(kernelSeconds:)) }
    public var stoppedAt: Date? { stoppedAtSeconds.swift.map(Date.init(kernelSeconds:)) }
    /// When it last finished doing something; nil while working.
    public var finishedAt: Date? { finishedAtSeconds.swift.map(Date.init(kernelSeconds:)) }
    /// How long it has run so far.
    public var duration: TimeInterval { durationSeconds(nowSeconds: KernelClock.now) }
    /// "1h 5m", "4m 30s", "12s".
    public var durationDescription: String { durationDescription(nowSeconds: KernelClock.now) }
    public var processIdentifier: Int? { processId.map { Int($0.int32Value) } }

    public static func == (lhs: Session, rhs: Session) -> Bool { lhs.isEqual(rhs) }
}

extension SessionMonitor {
    /// Every running session, in the order first seen.
    public var sessions: [Session] { KitObservation.track(); return sessionsUntracked }
    /// Recently finished sessions, newest first.
    public var recentSessions: [Session] { KitObservation.track(); return recentSessionsUntracked }
    /// The one most needing the person's eye first.
    public var sessionsByProminence: [Session] { KitObservation.track(); return sessionsByProminenceUntracked }
    public var activeSession: Session? { KitObservation.track(); return activeSessionUntracked }
    public var hasActiveSession: Bool { KitObservation.track(); return hasActiveSessionUntracked }
}

extension NotchActivity {
    public static func == (lhs: NotchActivity, rhs: NotchActivity) -> Bool { lhs.isEqual(rhs) }
}

extension NotchActivityResolver {
    /// How long a finished session keeps the notch.
    public static var defaultFinishedDisplayDuration: TimeInterval {
        NotchActivityResolver.companion.DEFAULT_FINISHED_DISPLAY_DURATION_SECONDS
    }

    /// The single activity worth showing now, or nil to stay hidden.
    public func resolve(sessions: [Session], quotas: [UsageQuota], headlineQuota: UsageQuota?, now: Date = Date()) -> NotchActivity? {
        resolve(sessions: sessions, quotas: quotas, headlineQuota: headlineQuota, nowSeconds: now.kernelSeconds)
    }
}

extension HookConstants {
    /// Set on the claude runs ClaudeBar spawns itself; the installed hook ignores them (#222).
    public static var probeEnvironmentKey: String { HookConstants.shared.PROBE_ENVIRONMENT_KEY }
}

extension NotchActivity {
    /// What the notch shows, to `switch` on.
    public enum Shape: Equatable, Sendable {
        case quotaGlance(UsageQuota)
        case working(Session)
        case agentsWorking(Session)
        case quotaThreshold(UsageQuota)
        case finished(Session)
        case awaitingInput(Session)
    }

    public var shape: Shape {
        switch onEnum(of: self) {
        case .quotaGlance(let a): .quotaGlance(a.quota)
        case .working(let a): .working(a.session)
        case .agentsWorking(let a): .agentsWorking(a.session)
        case .quotaThreshold(let a): .quotaThreshold(a.quota)
        case .finished(let a): .finished(a.session)
        case .awaitingInput(let a): .awaitingInput(a.session)
        }
    }
}

extension NotchActivityResolver {
    /// A finished session keeps the notch for the default time.
    public convenience init() {
        self.init(finishedDisplayDurationSeconds: NotchActivityResolver.defaultFinishedDisplayDuration)
    }
}
