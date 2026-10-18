import Foundation
import Mockable
import Testing
import Domain
@testable import Infrastructure

/// *Quota alerts* as a notification: the login, the person's percentage,
/// and what is left.
@Suite
struct QuotaAlertNotificationsTests {
    @Test func `should name the login, the percentage it fell below and what is left`() async {
        final class Sent: @unchecked Sendable { var title = "", body = "", category = "" }
        let sent = Sent()
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any)
            .willProduce { title, body, category in sent.title = title; sent.body = body; sent.category = category }

        await QuotaAlertNotifications(alertSender: sender).announce(QuotaAlert(login: "Claude · work", below: 35, left: 34))

        #expect(sent.title == "Claude · work is below 35%")
        #expect(sent.body == "34% left.")
        #expect(sent.category == QuotaAlertNotifications.category)
    }
}
