import Foundation
import Testing
@testable import Domain

/// *Login expiry*: told once per step — 7 days, 3 days, today — quiet
/// between steps and after renewal, and forever quiet about a login whose
/// sign-in has no knowable expiry or is already gone.
@MainActor
@Suite
struct LoginExpiryAlertsTests {
    /// The moment the decider reads as *now*, movable by a test.
    private final class Tick: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private let tick = Tick(Date(timeIntervalSince1970: 1_792_000_000))
    private let told = RecordingDestination()

    private func alerts() -> LoginExpiryAlerts {
        LoginExpiryAlerts(destination: told, calendar: .utc, now: { [tick] in tick.date })
    }

    /// A sign-in that ends `days` days from the moment the test is at.
    private func expires(inDays days: Int) -> Date {
        tick.date.addingTimeInterval(TimeInterval(days) * 24 * 3600)
    }

    /// Moves the moment the decider reads as *now*.
    private func advance(days: Int) {
        tick.date = tick.date.addingTimeInterval(TimeInterval(days) * 24 * 3600)
    }

    // MARK: - Telling

    @Test func `should warn once when a login expires within seven days`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude · work", provider: "claude", expiresAt: expires(inDays: 7))

        #expect(told.loginExpiryAlerts == [LoginExpiryAlert(login: "Claude · work", providerId: "claude", days: 7)])
    }

    @Test func `should say a sign-in that ends today is told in days zero`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude · work", provider: "claude", expiresAt: expires(inDays: 0))

        #expect(told.loginExpiryAlerts.map(\.days) == [0])
    }

    @Test func `should tell each step once and stay quiet between steps`() async {
        let alerts = alerts()

        // Ten days out: no step yet. Then the ladder down.
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 10))
        advance(days: 2)                              // 8 left
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 8))
        advance(days: 1)                              // 7 left
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 7))
        advance(days: 3)                              // 4 left
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 4))
        advance(days: 1)                              // 3 left
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 3))
        advance(days: 2)                              // 1 left
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 1))
        advance(days: 1)                              // today
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 0))

        #expect(told.loginExpiryAlerts.map(\.days) == [7, 3, 0])
    }

    @Test func `should stay quiet once the sign-in has expired`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: -1))

        #expect(told.loginExpiryAlerts.isEmpty)
    }

    // MARK: - The ladder resets

    @Test func `should start a fresh ladder when the expiry moves`() async {
        let alerts = alerts()
        let oldSignin = expires(inDays: 3)
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: oldSignin)

        // The same sign-in a day later: the step was told, so quiet.
        advance(days: 1)
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: oldSignin)
        // Signed in again: a new sign-in, three days out, says so again.
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: expires(inDays: 3))

        #expect(told.loginExpiryAlerts.map(\.days) == [3, 3])
    }

    @Test func `should forget the ladder when a refresh finds no expiry anymore`() async {
        let alerts = alerts()
        let signin = expires(inDays: 7)
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: signin)

        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: nil)
        await alerts.review("claude", named: "Claude", provider: "claude", expiresAt: signin)

        #expect(told.loginExpiryAlerts.map(\.days) == [7, 7])
    }

    // MARK: - Each login on its own

    @Test func `should judge logins apart`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude · work", provider: "claude", expiresAt: expires(inDays: 7))
        await alerts.review("claude", named: "Claude · work", provider: "claude", expiresAt: expires(inDays: 7))
        await alerts.review("codex.personal", named: "Codex", provider: "codex", expiresAt: expires(inDays: 7))

        #expect(told.loginExpiryAlerts.map(\.providerId) == ["claude", "codex"])
    }
}
