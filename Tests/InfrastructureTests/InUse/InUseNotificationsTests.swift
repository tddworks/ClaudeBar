import Foundation
import Mockable
import Testing
import Domain
@testable import Infrastructure

/// *In use* news as a notification: what it says, and the one button that
/// acts on it through `claudebar://use`.
@Suite
struct InUseNotificationsTests {
    private final class Sent: @unchecked Sendable {
        var title = "", body = "", category = "", button = "", link: URL?
    }

    private func send(_ alert: InUseAlert) async -> Sent {
        let sent = Sent()
        let sender = MockAlertSender()
        given(sender).send(title: .any, body: .any, categoryIdentifier: .any, button: .any, link: .any)
            .willProduce { title, body, category, button, link in
                sent.title = title; sent.body = body; sent.category = category; sent.button = button; sent.link = link
            }
        await InUseNotifications(alertSender: sender).announce(alert)
        return sent
    }

    private func alert(_ kind: InUseAlert.Kind, link: String) -> InUseAlert {
        InUseAlert(kind: kind, providerName: "Claude", from: "personal", to: "work", fromLeft: 8, toLeft: 81,
                   link: URL(string: link)!)
    }

    @Test
    func `should name the login worth moving to, what each has left, and offer one button to move`() async {
        let sent = await send(alert(.worthSwitching, link: "claudebar://use?provider=claude&account=work"))

        #expect(sent.title == "Claude: personal is at 8%")
        #expect(sent.body == "work has 81% left. Start new terminal sessions on work?")
        #expect(sent.button == "Use for New Sessions")
        #expect(sent.link?.absoluteString == "claudebar://use?provider=claude&account=work")
        #expect(sent.category == InUseNotifications.category)
    }

    @Test
    func `should say where new sessions go after a switch, with a button to undo it`() async {
        let sent = await send(alert(.switched, link: "claudebar://use?provider=claude&account=default"))

        #expect(sent.title == "New Claude sessions now use work")
        #expect(sent.body == "personal is at 8%. Sessions already running keep their login.")
        #expect(sent.button == "Undo")
        #expect(sent.link?.absoluteString == "claudebar://use?provider=claude&account=default")
    }
}
