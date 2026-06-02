import Foundation

/// Represents the type of usage quota being tracked.
/// Rich domain model with behavior - knows its own display name and duration.
public enum QuotaType: Sendable, Equatable, Hashable {
    /// Rolling 5-hour session limit
    case session
    /// Rolling 7-day weekly limit
    case weekly
    /// Model-specific limit (e.g., "opus", "sonnet")
    case modelSpecific(String)
    /// Generic time-based limit (e.g., "MCP Usage")
    case timeLimit(String)

    /// Human-readable display name for this quota type
    public var displayName: String {
        switch self {
        case .session:
            "Session"
        case .weekly:
            "Weekly"
        case .modelSpecific(let modelName):
            modelName.capitalized
        case .timeLimit(let name):
            name.capitalized
        }
    }

    /// Compact label used when several quota windows share the menu bar
    /// (e.g. "5h" + "7d"). Terser than `displayName` to conserve menu bar width.
    public var shortLabel: String {
        switch self {
        case .session:
            "5h"
        case .weekly:
            "7d"
        case .modelSpecific(let modelName):
            modelName.capitalized
        case .timeLimit(let name):
            name.capitalized
        }
    }

    /// Stable key used for persisted quota selection.
    public var quotaKey: String {
        switch self {
        case .session:
            "session"
        case .weekly:
            "weekly"
        case .modelSpecific(let modelName):
            "model:\(modelName)"
        case .timeLimit(let name):
            "time:\(name)"
        }
    }

    /// Creates a quota type from a persisted quota key.
    public init?(quotaKey: String) {
        switch quotaKey {
        case "session":
            self = .session
        case "weekly":
            self = .weekly
        default:
            if quotaKey.hasPrefix("model:") {
                let name = String(quotaKey.dropFirst("model:".count))
                guard !name.isEmpty else { return nil }
                self = .modelSpecific(name)
            } else if quotaKey.hasPrefix("time:") {
                let name = String(quotaKey.dropFirst("time:".count))
                guard !name.isEmpty else { return nil }
                self = .timeLimit(name)
            } else {
                return nil
            }
        }
    }

    /// The duration of the quota window
    public var duration: QuotaDuration {
        switch self {
        case .session:
            .hours(5)
        case .weekly:
            .days(7)
        case .modelSpecific:
            .days(7) // Model-specific limits typically follow weekly windows
        case .timeLimit(let name) where name.localizedCaseInsensitiveCompare("Monthly") == .orderedSame:
            .days(30)
        case .timeLimit:
            .days(7) // Generic time limits default to weekly
        }
    }

    /// The model name if this is a model-specific quota, nil otherwise
    public var modelName: String? {
        switch self {
        case .modelSpecific(let name):
            name
        default:
            nil
        }
    }
}

/// Represents a time duration for quota windows.
public enum QuotaDuration: Sendable, Equatable, Hashable {
    case hours(Int)
    case days(Int)

    /// Duration in seconds
    public var seconds: TimeInterval {
        switch self {
        case .hours(let h):
            TimeInterval(h * 3600)
        case .days(let d):
            TimeInterval(d * 24 * 3600)
        }
    }

    /// Human-readable description
    public var description: String {
        switch self {
        case .hours(let h):
            "\(h) hour\(h == 1 ? "" : "s")"
        case .days(let d):
            "\(d) day\(d == 1 ? "" : "s")"
        }
    }
}
