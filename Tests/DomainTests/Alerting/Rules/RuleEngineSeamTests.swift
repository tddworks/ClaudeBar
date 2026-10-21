import Foundation
import Testing
import Mockable
@testable import Domain
@testable import Infrastructure

/// The seam a rule follows a refresh through: `QuotaMonitor.onRefreshed`. A
/// login the person paused is never refreshed, so `onRefreshed` never runs for
/// it and no rule ever judges one (CANONICAL §5) — the Monitor is not edited to
/// say so.
@MainActor
@Suite
struct RuleEngineSeamTests {
    private final class Kept: RuleRepository, @unchecked Sendable {
        var stored: [Rule] = []
        var urls: [String: String] = [:]
        func rules() -> [Rule] { stored }
        func setRules(_ rules: [Rule]) { stored = rules }
        func webhookURL(forRule ruleId: String) -> String? { urls[ruleId] }
        func setWebhookURL(_ url: String?, forRule ruleId: String) { urls[ruleId] = url }
    }

    private final class Sent: WebhookSending, @unchecked Sendable {
        var bodies: [WebhookBody] = []
        func send(_ body: WebhookBody, forRule ruleId: String) async throws { bodies.append(body) }
    }

    private func usage(_ left: Double) -> UsageSnapshot {
        UsageSnapshot(providerId: "claude",
                      quotas: [UsageQuota(left: .share(left), quotaType: .session, providerId: "claude")],
                      capturedAt: Date())
    }

    @Test func `should never review a login the person paused`() async {
        // Given — a product watched by a monitor, and a rule that would fire at 9% left
        let settings = MockRepositoryFactory.makeSettingsRepository()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(usage(9))
        let product = stubbedProduct("claude", probe: probe, settings: settings)
        let monitor = QuotaMonitor(providers: kept([product]))

        let sent = Sent()
        let set = RuleSet(repository: Kept())
        set.add(Rule(condition: .below(percent: 35), action: .webhook(channel: .slack)),
                webhookURL: "https://example.test/hook")
        let engine = RuleEngine(set: set, sender: sent)
        monitor.onRefreshed { refreshed in
            await engine.review(
                RuleLogin(id: refreshed.id, providerId: refreshed.providerId,
                          name: monitor.lineupName(of: refreshed), usage: monitor.usage(of: refreshed)),
                under: monitor.statusPolicy
            )
        }

        // When — it refreshes once, she pauses the login, and it refreshes again
        await monitor.refresh(providerId: "claude")
        monitor.pause(product.defaultAccount)
        await monitor.refreshAll()

        // Then — one send, for the one refresh the login was watched for
        #expect(sent.bodies.count == 1)
    }
}