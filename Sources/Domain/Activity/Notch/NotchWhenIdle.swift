import Foundation

/// *When Nothing's Happening* — what the notch does while no session, finished
/// flash or low quota has anything to say (Settings → General, #627).
public enum NotchWhenIdle: String, Sendable, CaseIterable {
    /// The headline quota at a glance: the notch's resting state.
    case showQuota
    /// Nothing: the notch is away until something is happening.
    case hide

    /// The quota, so nobody's notch changes until they choose.
    public static let `default`: NotchWhenIdle = .showQuota
}
