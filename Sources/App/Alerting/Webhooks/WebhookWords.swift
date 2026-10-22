import Foundation
import Domain

/// The Webhooks card's words (design-concept/webhooks). The domain answers
/// with cases; what the person reads is here.
enum WebhookWords {
    static let title = "Webhooks"
    static let subtitle = "Send these alerts to Slack or a URL you own, as well as this Mac."
    static let add = "Add Webhook"
    static let emptyTitle = "No webhooks yet"
    static let emptyHint = "Add a Slack or JSON URL, and your quota alerts go there too."
    static let sendTest = "Send a test"
    static let edit = "Edit"
    static let cancel = "Cancel"
    static let remove = "Remove"
    static let save = "Save"
    static let urlLabel = "URL"
    static let urlPlaceholder = "https://hooks.slack.com/services/…"
    static let urlUnchanged = "Unchanged — paste a new URL to replace it"
    static let nameLabel = "NAME"
    static let namePlaceholder = "the URL's host"
    static let channelLabel = "CHANNEL"
    static let scopeLabel = "FOR"
    static let sendsLabel = "SENDS"
    static let quotaAlerts = "Quota alerts"
    static let statusAlerts = "Status alerts"
    static let statusAlertsHint = "When a login gets worse: running low, critically low, depleted"
    static let recap = "Weekly recap"
    static let recapHint = "When your week turns: the week that closed, across every provider"
    static let inKeychain = "Stored in the Keychain — a Slack URL carries a token. Never written to settings.json or a log."
    static let outsideKeychain = "This build can’t use the Keychain, so the URL is kept in ClaudeBar’s app credential store instead — not encrypted beyond your account’s file protection. A release build keeps it in the Keychain."
    static let listOutsideKeychain = "This build can’t use the Keychain, so these URLs are kept in the app credential store."

    static func editTitle(_ name: String) -> String { "Edit \(name)" }

    /// *Your percentages above: 60%, 35%*.
    static func quotaAlertsHint(_ percents: [Int]) -> String {
        percents.isEmpty ? "Your percentages above — none yet" : "Your percentages above: " + percents.map { "\($0)%" }.joined(separator: ", ")
    }

    static func channel(_ channel: WebhookChannel) -> String {
        switch channel {
        case .slack: "Slack"
        case .json: "JSON"
        }
    }

    static func scope(_ scope: Webhook.Scope, names: [String: String]) -> String {
        switch scope {
        case .everyLogin: "Every login"
        case .provider(let id): names[id] ?? id
        }
    }

    static func sends(_ sends: Webhook.Sends) -> String {
        [sends.quotaAlerts ? quotaAlerts : nil, sends.statusAlerts ? statusAlerts : nil,
         sends.recap ? recap : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func delivery(_ delivery: WebhookDelivery, now: Date) -> String {
        switch delivery {
        case .neverSent: "Nothing sent yet"
        case .sending: "Sending…"
        case .sent(let at): "Sent \(ago(at, now: now))"
        case .failed(let failure, _): "Failed — \(code(failure))"
        }
    }

    static func code(_ failure: WebhookFailure) -> String {
        switch failure {
        case .status(let status): "\(status)"
        case .timedOut: "timed out"
        case .unreachable: "unreachable"
        case .redirectedAway: "redirected"
        case .noURL: "no URL"
        }
    }

    static func failureHelp(_ failure: WebhookFailure) -> String {
        switch failure {
        case .status(404), .status(410): "The URL wasn’t found — it may be wrong or revoked."
        case .status(401), .status(403): "The URL refused it — its token may be revoked."
        case .timedOut: "No answer within 10 seconds."
        case .unreachable: "The host couldn’t be reached."
        case .redirectedAway: "The URL sent it to another site, which ClaudeBar never follows."
        case .noURL: "Its URL is no longer kept — edit it and paste the URL again."
        case .status: "The last send didn’t arrive."
        }
    }

    /// The line under a failure: what happens next.
    static func failure(_ failure: WebhookFailure) -> String {
        "Failed — \(code(failure)). \(failureHelp(failure)) The alert isn’t sent again — check the URL, then send a test."
    }

    static func refusal(_ refusal: Webhooks.Refusal) -> String {
        switch refusal {
        case .address(.notAURL): "Paste a full URL, starting https://"
        case .address(.notHTTPS): "Use an https URL — http is only for this Mac or your network."
        case .sendsNothing: "Tick at least one kind of alert."
        }
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return switch seconds {
        case ..<60: "just now"
        case ..<3600: "\(seconds / 60)m ago"
        case ..<86_400: "\(seconds / 3600)h ago"
        default: "\(seconds / 86_400)d ago"
        }
    }
}
