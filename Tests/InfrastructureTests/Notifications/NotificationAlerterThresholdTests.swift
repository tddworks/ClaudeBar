import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for the below-threshold alert delivery in NotificationAlerter
/// (issue #68). The crossing decision lives in QuotaMonitor; here the alerter
/// is handed a crossing and must name the user's threshold in the notification.
@Suite
struct NotificationAlerterThresholdTests {

    /// Records sends without touching UNUserNotificationCenter.
    private actor RecordingSender: AlertSender {
        private var sendsStorage: [(title: String, body: String, categoryIdentifier: String)] = []

        var sends: [(title: String, body: String, categoryIdentifier: String)] { sendsStorage }

        func requestPermission() async -> Bool { true }

        func send(title: String, body: String, categoryIdentifier: String) async throws {
            sendsStorage.append((title, body, categoryIdentifier))
        }
    }

    @Test
    func `threshold alert names the user threshold in the body`() async {
        let sender = RecordingSender()
        let alerter = NotificationAlerter(alertSender: sender)

        await alerter.alertThresholdCrossed(
            providerId: "claude",
            percentRemaining: 30,
            threshold: QuotaAlertThreshold(percent: 35)
        )

        let sends = await sender.sends
        #expect(sends.count == 1)
        #expect(sends.first?.title == "Claude Quota Alert")
        #expect(sends.first?.body.contains("35%") == true)
        #expect(sends.first?.body.contains("Claude") == true)
        #expect(sends.first?.categoryIdentifier == "QUOTA_THRESHOLD")
    }

    @Test
    func `threshold alert shows the remaining percentage`() async {
        let sender = RecordingSender()
        let alerter = NotificationAlerter(alertSender: sender)

        await alerter.alertThresholdCrossed(
            providerId: "codex",
            percentRemaining: 9.6,
            threshold: QuotaAlertThreshold(percent: 10)
        )

        #expect(await sender.sends.first?.body.contains("10%") == true)
        #expect(await sender.sends.first?.title == "Codex Quota Alert")
    }

    @Test
    func `fractional thresholds render without trailing zeros`() async {
        let sender = RecordingSender()
        let alerter = NotificationAlerter(alertSender: sender)

        await alerter.alertThresholdCrossed(
            providerId: "claude",
            percentRemaining: 12.4,
            threshold: QuotaAlertThreshold(percent: 12.5)
        )

        let body = await sender.sends.first?.body ?? ""
        #expect(body.contains("12.5%") == true)
        #expect(body.contains("12.50%") == false)
    }
}
