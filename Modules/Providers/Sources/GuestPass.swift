import Foundation
import Quotas

/// Represents Claude guest passes that can be shared with friends.
/// Each pass gives the recipient a free week of Claude Code.
public struct GuestPass: Sendable, Equatable {
    /// The number of guest passes remaining (nil if unknown)
    public let passesRemaining: Int?

    /// The referral URL to share with friends
    public let referralURL: URL

    // MARK: - Initialization

    public init(passesRemaining: Int? = nil, referralURL: URL) {
        self.passesRemaining = passesRemaining.map { max(0, $0) }
        self.referralURL = referralURL
    }

    // MARK: - Domain Behavior

    /// Whether there are passes available to share
    /// Returns true if count is unknown (we assume there might be passes)
    public var hasPassesAvailable: Bool {
        guard let count = passesRemaining else { return true }
        return count > 0
    }

    /// Human-readable display text for the pass count
    public var displayText: String {
        guard let count = passesRemaining else {
            return "Share Claude Code"
        }
        switch count {
        case 0:
            return "No passes left"
        case 1:
            return "1 pass left"
        default:
            return "\(count) passes left"
        }
    }
}
