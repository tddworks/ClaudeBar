import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// This Mac's notifications, for every kind of alert: the login as the lineup
/// names it, in the words the person has always read.
@Suite
struct NotificationsTests {
    private final class Sent: @unchecked Sendable { var title = "", body = "", category = "" }

    private func status(_ now: QuotaStatus, login: String = "Claude · work") -> Alert {
        .status(StatusAlert(login: login, providerId: "claude", was: .healthy, now: now))
    }

    private func sending(into sent: Sent) -> MockAlertSender {
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any)
            .willProduce { title, body, category in sent.title = title; sent.body = body; sent.category = category }
        return sender
    }

    // MARK: - Quota alerts

    @Test
    func `should name the login, the percentage it fell below and what is left`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent))
            .announce(.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34)))

        #expect(sent.title == "Claude · work is below 35%")
        #expect(sent.body == "34% left.")
        #expect(sent.category == Notifications.quotaAlertCategory)
    }

    // MARK: - Status alerts

    @Test
    func `should title a status alert with the login as the lineup names it`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent)).announce(status(.critical, login: "Codex · work"))

        #expect(sent.title == "Codex · work Quota Alert")
        #expect(sent.category == Notifications.statusAlertCategory)
    }

    @Test
    func `should say the quota is running low at warning`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent)).announce(status(.warning))

        #expect(sent.body == "Your Claude · work quota is running low. Consider pacing your usage.")
    }

    @Test
    func `should say the quota is critically low when critical`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent)).announce(status(.critical))

        #expect(sent.body == "Your Claude · work quota is critically low! Save important work.")
    }

    @Test
    func `should say the quota is depleted when it runs out`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent)).announce(status(.depleted))

        #expect(sent.body == "Your Claude · work quota is depleted. Usage may be blocked.")
    }

    // MARK: - Signed out

    @Test
    func `should say a login signed out, in the provider's own words for signing in again`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent))
            .announce(.signedOut(SignedOutAlert(login: "Claude · work", providerId: "claude",
                                                hint: "Run `claude` in terminal to log in again.")))

        #expect(sent.title == "Claude · work signed out")
        #expect(sent.body == "Run `claude` in terminal to log in again.")
        #expect(sent.category == Notifications.signedOutCategory)
    }

    @Test
    func `should ask to sign in again when the provider gives no hint`() async {
        let sent = Sent()

        await Notifications(alertSender: sending(into: sent))
            .announce(.signedOut(SignedOutAlert(login: "Claude · work", providerId: "claude", hint: nil)))

        #expect(sent.body == "Sign in again to see its usage.")
    }

    // MARK: - This Mac

    @Test
    func `should carry on quietly when the notification cannot be shown`() async {
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any).willThrow(NSError(domain: "test", code: 1))

        await Notifications(alertSender: sender).announce(status(.warning))
    }

    @Test
    func `should grant notification permission when macOS grants it`() async {
        let sender = MockAlertSender()
        given(sender).requestPermission().willReturn(true)

        #expect(await Notifications(alertSender: sender).requestPermission() == true)
    }

    @Test
    func `should rank each status worse than the one before`() {
        #expect(QuotaStatus.warning > .healthy)
        #expect(QuotaStatus.critical > .warning)
        #expect(QuotaStatus.depleted > .critical)
    }
}
