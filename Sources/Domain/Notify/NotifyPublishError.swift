import Foundation

/// Why a publish to Notify! did not land.
///
/// A dedicated type rather than a `ProbeError` case: every message here is
/// shown in the Notify pane, and half of them name an action only the user can
/// take on their phone. `ProbeError` speaks about fetching a quota from a
/// provider, which is the opposite direction of travel.
///
/// The gateway answers a missing token, a wrong token, an unknown device and
/// somebody else's device with one identical 403 so that it never confirms an
/// id exists, so `rejectedCredentials` deliberately covers all four.
public enum NotifyPublishError: Error, Sendable, Equatable, LocalizedError {
    /// No device id and token saved yet.
    case notLinked

    /// The gateway refused the credentials, or the device is not ours.
    case rejectedCredentials

    /// The device cannot show a Live Activity yet. Carries the gateway's own
    /// explanation, which distinguishes "the app has never been opened" from
    /// "Live Activities are switched off" from "several tiles are live".
    case liveActivityUnavailable(String)

    /// The tile was dismissed by the user or has already ended, so it can never
    /// be updated again. The driver forgets the handle and starts a fresh tile.
    case tileGone

    /// Push to start backoff after tiles that Apple accepted but never
    /// delivered. The ladder is 30 minutes after 2, 3 hours after 4, 6 hours
    /// after 6, and it resets the moment a tile appears.
    case backoff(retryAfter: TimeInterval, openingTheAppMayHelp: Bool)

    /// The gateway named a field it would not accept, or a per device ceiling
    /// was reached (5 live tiles, 10 widgets).
    case invalidPayload(String)

    /// A start where Apple never answered. A tile may exist, so the handle is
    /// kept and polled rather than started again, which could leave two tiles.
    case deliveryUnconfirmed(activityId: String?)

    /// The request never completed.
    case transportFailed(String)

    /// The gateway has this surface switched off server side. Home Screen
    /// widgets ship behind a kill switch, so a build that supports them can meet
    /// a service that is not serving them yet. Reads and deletes stay open, only
    /// creates and updates are refused, and the remedy is to wait rather than to
    /// change anything.
    case surfaceSwitchedOff(String)

    case unexpectedStatus(Int)

    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .notLinked:
            "Add your Notify! device ID and token before publishing."
        case .rejectedCredentials:
            "Notify! rejected these credentials. Copy the device ID and token again from the Notify! app."
        case .liveActivityUnavailable(let reason):
            reason.isEmpty
                ? "This device cannot show a Live Activity yet. Open the Notify! app once on the device."
                : reason
        case .tileGone:
            "The Live Activity was dismissed on the device. ClaudeBar will start a new one."
        case .backoff(let retryAfter, let openingTheAppMayHelp):
            openingTheAppMayHelp
                ? "Notify! is waiting \(Self.minutes(retryAfter)) before another Live Activity. Opening the Notify! app on the device may clear it sooner."
                : "Notify! is waiting \(Self.minutes(retryAfter)) before another Live Activity."
        case .invalidPayload(let message):
            message.isEmpty ? "Notify! rejected the content of this update." : message
        case .deliveryUnconfirmed:
            "Notify! could not confirm the Live Activity started. ClaudeBar will check again on the next update."
        case .transportFailed(let message):
            "Could not reach Notify!: \(message)"
        case .surfaceSwitchedOff(let message):
            message.isEmpty
                ? "Notify! has this widget switched off at the moment. ClaudeBar will try again later."
                : message
        case .unexpectedStatus(let code):
            "Notify! answered with HTTP \(code)."
        case .malformedResponse:
            "Notify! sent a response ClaudeBar could not read."
        }
    }

    /// How long to wait before trying again, when waiting is the remedy.
    public var retryAfter: TimeInterval? {
        switch self {
        case .backoff(let retryAfter, _): retryAfter
        default: nil
        }
    }

    /// Whether retrying the same request unchanged could ever succeed. Used to
    /// decide between backing off and giving up until something changes.
    public var isRetryable: Bool {
        switch self {
        case .transportFailed, .backoff, .deliveryUnconfirmed, .unexpectedStatus, .surfaceSwitchedOff:
            true
        case .notLinked, .rejectedCredentials, .liveActivityUnavailable, .tileGone,
             .invalidPayload, .malformedResponse:
            false
        }
    }

    private static func minutes(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded(.up))
        if minutes <= 1 { return "a minute" }
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = Int((Double(minutes) / 60).rounded())
        return hours == 1 ? "an hour" : "\(hours) hours"
    }
}
