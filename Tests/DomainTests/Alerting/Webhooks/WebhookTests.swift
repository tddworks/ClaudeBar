import Foundation
import Testing
@testable import Domain

/// A webhook wants an alert when it is on, sends that kind, and the alert's
/// provider is in its scope.
@Suite
struct WebhookTests {
    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Codex", providerId: "codex", was: .warning, now: .critical))
    private let expiry = Alert.loginExpiry(LoginExpiryAlert(login: "Claude · work", providerId: "claude", days: 3))

    private func webhook(scope: Webhook.Scope = .everyLogin, quotaAlerts: Bool = true,
                         statusAlerts: Bool = true, loginExpiryAlerts: Bool = true,
                         isOn: Bool = true) -> Webhook {
        Webhook(id: "1", name: "#ai-quota", channel: .slack, scope: scope,
                sends: Webhook.Sends(quotaAlerts: quotaAlerts, statusAlerts: statusAlerts,
                                     loginExpiryAlerts: loginExpiryAlerts),
                isOn: isOn)
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
        #expect(webhook(statusAlerts: false).wants(expiry))
        #expect(!webhook(loginExpiryAlerts: false).wants(expiry))
    }

    @Test func `should send none of the kinds it was saved without until they are ticked`() throws {
        let saved = try JSONDecoder().decode(Webhook.Sends.self,
                                             from: Data(#"{"quotaAlerts":true,"statusAlerts":true}"#.utf8))

        #expect(saved.quotaAlerts)
        #expect(saved.statusAlerts)
        #expect(!saved.loginExpiryAlerts)
        #expect(!saved.isNothing)
    }

    @Test func `should be nothing while it sends no kind at all`() {
        #expect(webhook(quotaAlerts: false, statusAlerts: false, loginExpiryAlerts: false).sends.isNothing)
        #expect(!webhook(quotaAlerts: false, statusAlerts: false, loginExpiryAlerts: true).sends.isNothing)
    }

    @Test func `should want only alerts about its provider's logins`() {
        #expect(webhook(scope: .provider("claude")).wants(quota))
        #expect(!webhook(scope: .provider("claude")).wants(status))
    }

    @Test func `should start with nothing sent`() {
        #expect(webhook().delivery == .neverSent)
    }
}
