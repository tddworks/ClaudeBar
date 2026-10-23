import Foundation
import Mockable
import Testing
import Domain
@testable import Infrastructure

/// *Rest when empty* news as a notification: what it says, and the one
/// button the App's link opens.
@Suite
struct RestNotificationsTests {
    private final class Sent: @unchecked Sendable {
        var title = "", body = "", category = "", button: String?, link: URL?
    }

    private func send(_ kind: RestNotice.Kind) async -> Sent {
        let sent = Sent()
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any, button: .any, link: .any)
            .willProduce { title, body, category, button, link in
                sent.title = title; sent.body = body; sent.category = category; sent.button = button; sent.link = link
            }
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any)
            .willProduce { title, body, category in
                sent.title = title; sent.body = body; sent.category = category
            }
        let notifications = RestNotifications(alertSender: sender,
                                              showAnywayLink: { URL(string: "claudebar://show-anyway?provider=\($0)")! })
        await notifications.announce(RestNotice(kind: kind, productName: "Claude", providerId: "claude"))
        return sent
    }

    @Test
    func `should say a product rests, with one button to show it anyway`() async {
        let sent = await send(.resting)

        #expect(sent.title == "Claude is resting")
        #expect(sent.body == "Every login has run out, so it is dimmed until a refresh shows room.")
        #expect(sent.button == "Show anyway")
        #expect(sent.link?.absoluteString == "claudebar://show-anyway?provider=claude")
        #expect(sent.category == RestNotifications.category)
    }

    @Test
    func `should say a product is back, with no button`() async {
        let sent = await send(.back)

        #expect(sent.title == "Claude is back")
        #expect(sent.body == "A reset gave it room again.")
        #expect(sent.button == nil)
    }
}
