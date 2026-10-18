import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Tests for NotificationAlerter.
@Suite(.serialized)
struct NotificationAlerterTests {

    // MARK: - Should Alert Tests

    @Test
    func `should alert when a quota is at warning`() {
        let alerter = NotificationAlerter()

        #expect(alerter.shouldAlert(for: .warning) == true)
    }

    @Test
    func `should alert when a quota is critical`() {
        let alerter = NotificationAlerter()

        #expect(alerter.shouldAlert(for: .critical) == true)
    }

    @Test
    func `should alert when a quota is depleted`() {
        let alerter = NotificationAlerter()

        #expect(alerter.shouldAlert(for: .depleted) == true)
    }

    @Test
    func `should not alert when a quota is healthy`() {
        let alerter = NotificationAlerter()

        #expect(alerter.shouldAlert(for: .healthy) == false)
    }

    // MARK: - Provider Display Name Tests

    @Test
    func `should name each known provider as the person knows it`() {
        let alerter = NotificationAlerter()

        // Then - returns correct provider names
        #expect(alerter.providerDisplayName(for: "claude") == "Claude")
        #expect(alerter.providerDisplayName(for: "codex") == "Codex")
        #expect(alerter.providerDisplayName(for: "gemini") == "Gemini")
        #expect(alerter.providerDisplayName(for: "copilot") == "Copilot")
        #expect(alerter.providerDisplayName(for: "antigravity") == "Antigravity")
        #expect(alerter.providerDisplayName(for: "zai") == "Z.ai")
        #expect(alerter.providerDisplayName(for: "minimax") == "MiniMax")
        #expect(alerter.providerDisplayName(for: "alibaba") == "Alibaba")
        #expect(alerter.providerDisplayName(for: "omp") == "Oh My Pi")
    }

    @Test
    func `should capitalise the id of a provider it does not know`() {
        // Given - unknown provider IDs (not in registry)
        let alerter = NotificationAlerter()

        // Then - capitalizes the ID
        #expect(alerter.providerDisplayName(for: "unknown") == "Unknown")
        #expect(alerter.providerDisplayName(for: "chatgpt") == "Chatgpt")
    }

    // MARK: - Alert Body Tests

    @Test
    func `should say the provider is running low at warning`() {
        let alerter = NotificationAlerter()

        let body = alerter.alertBody(for: .warning, providerName: "Claude")

        #expect(body.contains("Claude"))
        #expect(body.contains("running low"))
    }

    @Test
    func `should say the provider is critically low when critical`() {
        let alerter = NotificationAlerter()

        let body = alerter.alertBody(for: .critical, providerName: "Codex")

        #expect(body.contains("Codex"))
        #expect(body.contains("critically low"))
    }

    @Test
    func `should say the provider is depleted when depleted`() {
        let alerter = NotificationAlerter()

        let body = alerter.alertBody(for: .depleted, providerName: "Gemini")

        #expect(body.contains("Gemini"))
        #expect(body.contains("depleted"))
    }

    @Test
    func `should say the provider has recovered when healthy again`() {
        let alerter = NotificationAlerter()

        let body = alerter.alertBody(for: .healthy, providerName: "Claude")

        #expect(body.contains("Claude"))
        #expect(body.contains("recovered"))
    }

    // MARK: - Status Degradation Detection (Domain Logic)

    @Test
    func `should rank warning as worse than healthy`() {
        #expect(QuotaStatus.warning > QuotaStatus.healthy)
    }

    @Test
    func `should rank critical as worse than warning`() {
        #expect(QuotaStatus.critical > QuotaStatus.warning)
    }

    @Test
    func `should rank depleted as worse than critical`() {
        #expect(QuotaStatus.depleted > QuotaStatus.critical)
    }

    @Test
    func `should rank healthy as better than warning`() {
        #expect(QuotaStatus.healthy < QuotaStatus.warning)
    }

    @Test
    func `should rank a status equal to itself`() {
        #expect(QuotaStatus.healthy == QuotaStatus.healthy)
    }

    // MARK: - Alert Integration Tests

    @Test
    func `should notify that the quota is running low when it drops to warning`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        await alerter.alert(providerId: "claude", previousStatus: .healthy, currentStatus: .warning)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains("running low") },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test
    func `should notify that the quota is critically low when it drops to critical`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        await alerter.alert(providerId: "codex", previousStatus: .warning, currentStatus: .critical)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains("critically low") },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test
    func `should notify that the quota is depleted when it runs out`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willReturn(())
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        await alerter.alert(providerId: "gemini", previousStatus: .critical, currentStatus: .depleted)

        // Then
        verify(mockSender).send(
            title: .matching { $0.contains("Quota Alert") },
            body: .matching { $0.contains("depleted") },
            categoryIdentifier: .value("QUOTA_ALERT")
        ).called(1)
    }

    @Test
    func `should not notify when the quota recovers`() async {
        // Given
        let mockSender = MockAlertSender()
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When - status improves from warning to healthy
        await alerter.alert(providerId: "claude", previousStatus: .warning, currentStatus: .healthy)

        // Then - no alert sent
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(0)
    }

    @Test
    func `should not notify when the quota's status stays the same`() async {
        // Given
        let mockSender = MockAlertSender()
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When - status stays the same
        await alerter.alert(providerId: "claude", previousStatus: .warning, currentStatus: .warning)

        // Then - no alert sent
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(0)
    }

    @Test
    func `should carry on quietly when the notification cannot be shown`() async {
        // Given - sender throws an error
        let mockSender = MockAlertSender()
        given(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).willThrow(NSError(domain: "test", code: 1))
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When & Then - should not throw
        await alerter.alert(providerId: "claude", previousStatus: .healthy, currentStatus: .warning)

        // Verify alert was attempted
        verify(mockSender).send(title: .any, body: .any, categoryIdentifier: .any).called(1)
    }

    @Test
    func `should grant notification permission when macOS grants it`() async {
        // Given
        let mockSender = MockAlertSender()
        given(mockSender).requestPermission().willReturn(true)
        let alerter = NotificationAlerter(alertSender: mockSender)

        // When
        let result = await alerter.requestPermission()

        // Then
        #expect(result == true)
        verify(mockSender).requestPermission().called(1)
    }
}
