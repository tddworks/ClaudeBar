import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// *Status alerts* as a notification: the login as the lineup names it, and
/// the status it got worse to.
@Suite
struct NotificationAlerterTests {
    private final class Sent: @unchecked Sendable { var title = "", body = "", category = "" }

    private func alert(_ now: QuotaStatus, login: String = "Claude · work") -> Alert {
        .status(StatusAlert(login: login, providerId: "claude", was: .healthy, now: now))
    }

    private func sending(into sent: Sent) -> MockAlertSender {
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any)
            .willProduce { title, body, category in sent.title = title; sent.body = body; sent.category = category }
        return sender
    }

    @Test
    func `should title the notification with the login as the lineup names it`() async {
        let sent = Sent()

        await NotificationAlerter(alertSender: sending(into: sent)).announce(alert(.critical, login: "Codex · work"))

        #expect(sent.title == "Codex · work Quota Alert")
        #expect(sent.category == "QUOTA_ALERT")
    }

    @Test
    func `should say the quota is running low at warning`() async {
        let sent = Sent()

        await NotificationAlerter(alertSender: sending(into: sent)).announce(alert(.warning))

        #expect(sent.body == "Your Claude · work quota is running low. Consider pacing your usage.")
    }

    @Test
    func `should say the quota is critically low when critical`() async {
        let sent = Sent()

        await NotificationAlerter(alertSender: sending(into: sent)).announce(alert(.critical))

        #expect(sent.body == "Your Claude · work quota is critically low! Save important work.")
    }

    @Test
    func `should say the quota is depleted when it runs out`() async {
        let sent = Sent()

        await NotificationAlerter(alertSender: sending(into: sent)).announce(alert(.depleted))

        #expect(sent.body == "Your Claude · work quota is depleted. Usage may be blocked.")
    }

    @Test
    func `should carry on quietly when the notification cannot be shown`() async {
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any).willThrow(NSError(domain: "test", code: 1))

        await NotificationAlerter(alertSender: sender).announce(alert(.warning))
    }

    @Test
    func `should grant notification permission when macOS grants it`() async {
        let sender = MockAlertSender()
        given(sender).requestPermission().willReturn(true)

        #expect(await NotificationAlerter(alertSender: sender).requestPermission() == true)
    }

    // MARK: - How statuses rank

    @Test
    func `should rank each status worse than the one before`() {
        #expect(QuotaStatus.warning > .healthy)
        #expect(QuotaStatus.critical > .warning)
        #expect(QuotaStatus.depleted > .critical)
    }
}
