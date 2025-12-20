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

    /// Human-readable display name for this quota type
    public var displayName: String {
        switch self {
        case .session:
            "Current Session"
        case .weekly:
            "Weekly"
        case .modelSpecific(let modelName):
            modelName.capitalized
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
