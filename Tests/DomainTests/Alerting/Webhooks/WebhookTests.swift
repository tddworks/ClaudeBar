import Foundation
import Testing
@testable import Domain

/// A webhook wants an alert when it is on, sends that kind, and the alert's
/// provider is in its scope.
@Suite
struct WebhookTests {
    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Codex", providerId: "codex", was: .warning, now: .critical))

    private func webhook(scope: Webhook.Scope = .everyLogin, quotaAlerts: Bool = true,
                         statusAlerts: Bool = true, isOn: Bool = true) -> Webhook {
        Webhook(id: "1", name: "#ai-quota", channel: .slack, scope: scope,
                sends: Webhook.Sends(quotaAlerts: quotaAlerts, statusAlerts: statusAlerts), isOn: isOn)
    }

    @Test func `should want every alert when it sends both kinds for every login`() {
        #expect(webhook().wants(quota))
        #expect(webhook().wants(status))
    }

    @Test func `should want nothing while it is off`() {
        #expect(!webhook(isOn: false).wants(quota))
        #expect(!webhook(isOn: false).wants(status))
    }

    @Test func `should want only the kinds it sends`() {
        #expect(!webhook(quotaAlerts: false).wants(quota))
        #expect(webhook(quotaAlerts: false).wants(status))
        #expect(!webhook(statusAlerts: false).wants(status))
    }

    @Test func `should want only alerts about its provider's logins`() {
        #expect(webhook(scope: .provider("claude")).wants(quota))
        #expect(!webhook(scope: .provider("claude")).wants(status))
    }

    @Test func `should start with nothing sent`() {
        #expect(webhook().delivery == .neverSent)
    }
}
