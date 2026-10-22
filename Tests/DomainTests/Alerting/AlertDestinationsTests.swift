import Foundation
import Testing
@testable import Domain

/// Every alert goes to every destination; each destination says what it does
/// with it.
@Suite
struct AlertDestinationsTests {
    private let quota = Alert.quota(QuotaAlert(login: "Claude · work", providerId: "claude", below: 35, left: 34))
    private let status = Alert.status(StatusAlert(login: "Codex", providerId: "codex", was: .warning, now: .critical))

    @Test func `should tell every destination each alert`() async {
        let mac = RecordingDestination(), team = RecordingDestination()

        await AlertDestinations([mac, team]).announce(quota)
        await AlertDestinations([mac, team]).announce(status)

        #expect(mac.alerts == [quota, status])
        #expect(team.alerts == [quota, status])
    }

    @Test func `should name the login and its provider whatever the kind`() {
        #expect(quota.login == "Claude · work")
        #expect(quota.providerId == "claude")
        #expect(status.login == "Codex")
        #expect(status.providerId == "codex")
    }
}
