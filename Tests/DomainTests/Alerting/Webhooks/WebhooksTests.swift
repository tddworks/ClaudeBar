import Foundation
import Testing
@testable import Domain

/// *Webhooks*: the person's list — added, edited, turned off, removed — and a
/// destination that sends each alert to every webhook that wants it.
@MainActor
@Suite
struct WebhooksTests {
    private let settings = InMemoryWebhookSettings()
    private let secrets = InMemoryDestinationSecrets()
    private let now = Date(timeIntervalSince1970: 1_792_662_060)
    private let slackURL = "https://hooks.slack.com/services/T000/B000/XXXX"
    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Codex", providerId: "codex", was: .warning, now: .critical))

    private func webhooks(sender: RecordingWebhookSender = RecordingWebhookSender(),
                          secrets: InMemoryDestinationSecrets? = nil) -> Webhooks {
        var next = 0
        return Webhooks(settings: settings, secrets: secrets ?? self.secrets, sender: sender,
                        now: { [now] in now }, makeId: { next += 1; return "id\(next)" })
    }

    private let both = Webhook.Sends(quotaAlerts: true, statusAlerts: true)

    @discardableResult
    private func add(_ webhooks: Webhooks, url: String? = nil, name: String = "", channel: WebhookChannel = .slack,
                     scope: Webhook.Scope = .everyLogin, sends: Webhook.Sends? = nil) throws -> Webhook {
        try webhooks.add(url: url ?? slackURL, name: name, channel: channel, scope: scope, sends: sends ?? both)
    }

    // MARK: - Adding

    @Test func `should name a webhook for its URL's host until the person types a name`() throws {
        let webhooks = webhooks()

        try add(webhooks)
        try add(webhooks, url: "https://ops.example.com/hook", name: "pause-jobs")

        #expect(webhooks.list.map(\.name) == ["hooks.slack.com", "pause-jobs"])
        #expect(webhooks.list.map(\.host) == ["hooks.slack.com", "ops.example.com"])
    }

    @Test func `should add a webhook switched on, with nothing sent yet`() throws {
        let webhook = try add(webhooks())

        #expect(webhook.isOn)
        #expect(webhook.delivery == .neverSent)
    }

    @Test func `should keep the URL as a secret and save the rest`() throws {
        let webhook = try add(webhooks(), name: "#ai-quota")

        #expect(secrets.get(forKey: Webhooks.secretKey(for: webhook.id)) == slackURL)
        #expect(settings.saved.map(\.name) == ["#ai-quota"])
    }

    @Test func `should refuse an http URL to a host on the internet, and add nothing`() {
        let webhooks = webhooks()

        #expect(throws: Webhooks.Refusal.address(.notHTTPS)) { try add(webhooks, url: "http://ops.example.com/hook") }
        #expect(webhooks.list.isEmpty)
        #expect(secrets.keychain.isEmpty)
    }

    @Test func `should refuse a webhook that sends nothing`() {
        let webhooks = webhooks()

        #expect(throws: Webhooks.Refusal.sendsNothing) {
            try add(webhooks, sends: Webhook.Sends(quotaAlerts: false, statusAlerts: false))
        }
    }

    // MARK: - The saved list

    @Test func `should bring back the saved webhooks with their hosts and nothing sent yet`() throws {
        let first = webhooks()
        let added = try add(first, name: "#ai-quota")

        let relaunched = webhooks()

        #expect(relaunched.list.map(\.id) == [added.id])
        #expect(relaunched.list.first?.host == "hooks.slack.com")
        #expect(relaunched.list.first?.delivery == .neverSent)
    }

    @Test func `should say the URLs are kept outside the Keychain when it refuses them`() throws {
        let refused = InMemoryDestinationSecrets(keychainRefuses: true)
        let webhooks = webhooks(secrets: refused)

        #expect(!webhooks.urlsAreOutsideKeychain)
        try add(webhooks)

        #expect(webhooks.urlsAreOutsideKeychain)
        #expect(!self.webhooks().urlsAreOutsideKeychain)
    }

    // MARK: - Changing one

    @Test func `should keep a webhook that is turned off, with its URL and its last delivery`() async throws {
        let webhooks = webhooks()
        let webhook = try add(webhooks)
        await webhooks.sendTest(webhook.id)

        webhooks.turn(webhook.id, on: false)

        #expect(webhooks.list.first?.isOn == false)
        #expect(webhooks.list.first?.delivery == .sent(at: now))
        #expect(settings.saved.first?.isOn == false)
        #expect(secrets.get(forKey: Webhooks.secretKey(for: webhook.id)) == slackURL)
    }

    @Test func `should change what a webhook sends and keep its URL when none is pasted`() throws {
        let webhooks = webhooks()
        let webhook = try add(webhooks)

        try webhooks.edit(webhook.id, url: nil, name: "team", channel: .json, scope: .provider("claude"),
                          sends: Webhook.Sends(quotaAlerts: false, statusAlerts: true))

        let edited = try #require(webhooks.list.first)
        #expect(edited.name == "team")
        #expect(edited.channel == .json)
        #expect(edited.scope == .provider("claude"))
        #expect(edited.sends == Webhook.Sends(quotaAlerts: false, statusAlerts: true))
        #expect(settings.saved == [edited])
        #expect(secrets.get(forKey: Webhooks.secretKey(for: webhook.id)) == slackURL)
    }

    @Test func `should replace the URL and forget the last delivery when a new one is pasted`() async throws {
        let webhooks = webhooks()
        let webhook = try add(webhooks)
        await webhooks.sendTest(webhook.id)

        try webhooks.edit(webhook.id, url: "https://ops.example.com/hook", name: "", channel: .slack,
                          scope: .everyLogin, sends: both)

        #expect(webhooks.list.first?.host == "ops.example.com")
        #expect(webhooks.list.first?.name == "ops.example.com")
        #expect(webhooks.list.first?.delivery == .neverSent)
        #expect(secrets.get(forKey: Webhooks.secretKey(for: webhook.id)) == "https://ops.example.com/hook")
    }

    @Test func `should refuse an edit to a URL it would refuse to add`() throws {
        let webhooks = webhooks()
        let webhook = try add(webhooks)

        #expect(throws: Webhooks.Refusal.address(.notAURL)) {
            try webhooks.edit(webhook.id, url: "hooks.slack.com", name: "", channel: .slack, scope: .everyLogin, sends: both)
        }
        #expect(secrets.get(forKey: Webhooks.secretKey(for: webhook.id)) == slackURL)
    }

    @Test func `should remove a webhook and its URL`() throws {
        let webhooks = webhooks()
        let webhook = try add(webhooks)

        webhooks.remove(webhook.id)

        #expect(webhooks.list.isEmpty)
        #expect(settings.saved.isEmpty)
        #expect(secrets.get(forKey: Webhooks.secretKey(for: webhook.id)) == nil)
    }

    // MARK: - Alerts

    @Test func `should send an alert to every webhook that wants it, and no other`() async throws {
        let sender = RecordingWebhookSender()
        let webhooks = webhooks(sender: sender)
        let team = try add(webhooks, name: "team")
        let claudeOnly = try add(webhooks, url: "https://claude.example.com/hook", scope: .provider("claude"))
        let off = try add(webhooks, url: "https://off.example.com/hook")
        webhooks.turn(off.id, on: false)

        await webhooks.announce(status)

        #expect(sender.posts.map(\.webhookId) == [team.id])
        #expect(webhooks.list.first { $0.id == claudeOnly.id }?.delivery == .neverSent)
        #expect(webhooks.list.first { $0.id == team.id }?.delivery == .sent(at: now))
    }

    @Test func `should send each webhook the body for its channel`() async throws {
        let sender = RecordingWebhookSender()
        let webhooks = webhooks(sender: sender)
        try add(webhooks, channel: .json)

        await webhooks.announce(quota)

        #expect(sender.posts.first?.body == WebhookBody(.alert(quota), channel: .json, sentAt: now).encoded())
        #expect(sender.posts.first?.address.host == "hooks.slack.com")
    }

    @Test func `should keep the failure and its code when a webhook refuses an alert`() async throws {
        let sender = RecordingWebhookSender(answers: ["hooks.slack.com": .failed(.status(404))])
        let webhooks = webhooks(sender: sender)
        try add(webhooks)

        await webhooks.announce(quota)

        #expect(webhooks.list.first?.delivery == .failed(.status(404), at: now))
    }

    @Test func `should fail without sending when a webhook's URL is gone`() async throws {
        let sender = RecordingWebhookSender()
        let webhooks = webhooks(sender: sender)
        let webhook = try add(webhooks)
        secrets.delete(forKey: Webhooks.secretKey(for: webhook.id))

        await webhooks.announce(quota)

        #expect(sender.posts.isEmpty)
        #expect(webhooks.list.first?.delivery == .failed(.noURL, at: now))
    }

    // MARK: - Send a test

    @Test func `should send a test, labelled a test, even to a webhook that is off`() async throws {
        let sender = RecordingWebhookSender()
        let webhooks = webhooks(sender: sender)
        let webhook = try add(webhooks)
        webhooks.turn(webhook.id, on: false)

        await webhooks.sendTest(webhook.id)

        #expect(sender.posts.first?.body == WebhookBody(.test, channel: .slack, sentAt: now).encoded())
        #expect(webhooks.list.first?.delivery == .sent(at: now))
    }
}
