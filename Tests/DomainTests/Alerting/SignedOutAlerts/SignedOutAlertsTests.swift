import Foundation
import Testing
@testable import Domain

/// *Signed out*: a login whose refresh failed because its sign-in ended is
/// told once, and told again only after a refresh with no error in between.
@MainActor
@Suite
struct SignedOutAlertsTests {
    private let told = RecordingDestination()
    private let signedOut = UsageError.sessionExpired(hint: "Run `claude` in terminal to log in again.")

    private func alerts() -> SignedOutAlerts { SignedOutAlerts(destination: told) }

    @Test func `should tell once that a login signed out, with what to run`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude · work", provider: "claude", lastError: signedOut)

        #expect(told.signedOutAlerts == [SignedOutAlert(login: "Claude · work", providerId: "claude",
                                                        hint: "Run `claude` in terminal to log in again.")])
    }

    @Test func `should stay quiet while a login stays signed out`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", lastError: signedOut)
        await alerts.review("claude", named: "Claude", provider: "claude", lastError: signedOut)

        #expect(told.signedOutAlerts.count == 1)
    }

    @Test func `should tell again after the login refreshed with no error in between`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", lastError: signedOut)
        await alerts.review("claude", named: "Claude", provider: "claude", lastError: nil)
        await alerts.review("claude", named: "Claude", provider: "claude", lastError: signedOut)

        #expect(told.signedOutAlerts.count == 2)
    }

    @Test func `should not tell again when another failure came between two sign-outs`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", lastError: signedOut)
        await alerts.review("claude", named: "Claude", provider: "claude", lastError: UsageError.timeout)
        await alerts.review("claude", named: "Claude", provider: "claude", lastError: signedOut)

        #expect(told.signedOutAlerts.count == 1)
    }

    @Test func `should stay quiet about a failure that is not a sign-out`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", lastError: UsageError.timeout)
        await alerts.review("claude", named: "Claude", provider: "claude", lastError: UsageError.authenticationRequired)

        #expect(told.alerts.isEmpty)
    }

    @Test func `should tell each login of a product on its own`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude · me", provider: "claude", lastError: signedOut)
        await alerts.review("claude.work", named: "Claude · work", provider: "claude", lastError: signedOut)

        #expect(told.signedOutAlerts.map(\.login) == ["Claude · me", "Claude · work"])
    }
}
