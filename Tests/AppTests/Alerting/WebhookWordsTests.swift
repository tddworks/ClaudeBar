import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// What the Webhooks card says, in the person's words.
@Suite
struct WebhookWordsTests {
    private let now = Date(timeIntervalSince1970: 1_792_662_060)

    @Test func `should say nothing was sent yet before the first send`() {
        #expect(WebhookWords.delivery(.neverSent, now: now) == "Nothing sent yet")
    }

    @Test func `should say how long ago the last send arrived`() {
        #expect(WebhookWords.delivery(.sent(at: now.addingTimeInterval(-120)), now: now) == "Sent 2m ago")
        #expect(WebhookWords.delivery(.sent(at: now), now: now) == "Sent just now")
    }

    @Test func `should name the code a failed send got`() {
        #expect(WebhookWords.delivery(.failed(.status(404), at: now), now: now) == "Failed — 404")
        #expect(WebhookWords.delivery(.failed(.timedOut, at: now), now: now) == "Failed — timed out")
    }

    @Test func `should explain a URL that wasn't found or was refused`() {
        #expect(WebhookWords.failureHelp(.status(404)) == "The URL wasn’t found — it may be wrong or revoked.")
        #expect(WebhookWords.failureHelp(.status(403)) == "The URL refused it — its token may be revoked.")
        #expect(WebhookWords.failureHelp(.timedOut) == "No answer within 10 seconds.")
    }

    @Test func `should word each refusal so the person can fix the form`() {
        #expect(WebhookWords.refusal(.address(.notHTTPS)) == "Use an https URL — http is only for this Mac or your network.")
        #expect(WebhookWords.refusal(.address(.notAURL)) == "Paste a full URL, starting https://")
        #expect(WebhookWords.refusal(.sendsNothing) == "Tick at least one kind of alert.")
    }

    @Test func `should name the scope by its provider, or every login`() {
        let names = ["claude": "Claude"]
        #expect(WebhookWords.scope(.everyLogin, names: names) == "Every login")
        #expect(WebhookWords.scope(.provider("claude"), names: names) == "Claude")
    }

    @Test func `should list what a webhook sends`() {
        #expect(WebhookWords.sends(Webhook.Sends(quotaAlerts: true, statusAlerts: true)) == "Quota alerts · Status alerts")
        #expect(WebhookWords.sends(Webhook.Sends(quotaAlerts: false, statusAlerts: true)) == "Status alerts")
        #expect(WebhookWords.sends(Webhook.Sends(quotaAlerts: false, statusAlerts: true, signedOutAlerts: true))
                == "Status alerts · Signed-out alerts")
        #expect(WebhookWords.sends(Webhook.Sends(quotaAlerts: false, statusAlerts: false, recap: true,
                                                 signedOutAlerts: true)) == "Weekly recap · Signed-out alerts")
    }

    @Test func `should name each channel as the card prints it`() {
        #expect(WebhookWords.channel(.slack) == "Slack")
        #expect(WebhookWords.channel(.json) == "JSON")
    }
}
