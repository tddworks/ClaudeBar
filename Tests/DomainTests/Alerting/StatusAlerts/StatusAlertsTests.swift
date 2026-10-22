import Foundation
import Testing
@testable import Domain

/// *Status alerts*: told once when a login's status gets worse under the
/// policy, never while it stays or recovers, each login on its own.
@MainActor
@Suite
struct StatusAlertsTests {
    private final class Told {
        let destination = RecordingDestination()
        var alerts: [StatusAlert] { destination.statusAlerts }
    }

    private let told = Told()

    private func alerts() -> StatusAlerts { StatusAlerts(destination: told.destination) }

    // MARK: - Telling

    @Test func `should tell when a login's status gets worse`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", status: .healthy)
        await alerts.review("claude", named: "Claude", provider: "claude", status: .warning)

        #expect(told.alerts == [StatusAlert(login: "Claude", providerId: "claude", was: .healthy, now: .warning)])
    }

    @Test func `should tell once when a login starts critical`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", status: .critical)

        #expect(told.alerts == [StatusAlert(login: "Claude", providerId: "claude", was: .healthy, now: .critical)])
    }

    @Test func `should tell each step down from low to depleted`() async {
        let alerts = alerts()

        for status in [QuotaStatus.warning, .critical, .depleted] {
            await alerts.review("claude", named: "Claude", provider: "claude", status: status)
        }

        #expect(told.alerts.map(\.now) == [.warning, .critical, .depleted])
        #expect(told.alerts.map(\.was) == [.healthy, .warning, .critical])
    }

    @Test func `should name the login as the lineup does, with its provider`() async {
        let alerts = alerts()

        await alerts.review("codex.work", named: "Codex · work", provider: "codex", status: .critical)

        #expect(told.alerts.first?.login == "Codex · work")
        #expect(told.alerts.first?.providerId == "codex")
    }

    // MARK: - Quiet

    @Test func `should stay quiet while a login's status stays the same`() async {
        let alerts = alerts()

        for _ in 0..<3 { await alerts.review("claude", named: "Claude", provider: "claude", status: .critical) }

        #expect(told.alerts.count == 1)
    }

    @Test func `should stay quiet while a login stays healthy`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", status: .healthy)
        await alerts.review("claude", named: "Claude", provider: "claude", status: .healthy)

        #expect(told.alerts.isEmpty)
    }

    @Test func `should stay quiet when a login improves or recovers`() async {
        let alerts = alerts()

        for status in [QuotaStatus.critical, .warning, .healthy] {
            await alerts.review("claude", named: "Claude", provider: "claude", status: status)
        }

        #expect(told.alerts.map(\.now) == [.critical])
    }

    @Test func `should tell again when a login gets worse after improving`() async {
        let alerts = alerts()

        for status in [QuotaStatus.critical, .warning, .critical] {
            await alerts.review("claude", named: "Claude", provider: "claude", status: status)
        }

        #expect(told.alerts.map(\.now) == [.critical, .critical])
        #expect(told.alerts.last?.was == .warning)
    }

    @Test func `should say nothing about a login with no usage`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude", provider: "claude", status: .critical)
        await alerts.review("claude", named: "Claude", provider: "claude", status: nil)
        await alerts.review("claude", named: "Claude", provider: "claude", status: .critical)

        #expect(told.alerts.count == 1)
    }

    @Test func `should judge two logins of one product apart`() async {
        let alerts = alerts()

        await alerts.review("claude", named: "Claude · me", provider: "claude", status: .critical)
        await alerts.review("claude.work", named: "Claude · work", provider: "claude", status: .critical)

        #expect(told.alerts.map(\.login) == ["Claude · me", "Claude · work"])
    }
}
