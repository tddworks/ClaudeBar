import Foundation
import Testing
@testable import Infrastructure
import Domain

/// The person's webhooks, kept in `settings.json` under `alerts.webhooks` —
/// everything but the URL.
@Suite
struct JSONSettingsRepositoryWebhookTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
    private var file: URL { directory.appendingPathComponent("settings.json") }

    private func repository() -> JSONSettingsRepository {
        JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
    }

    private let team = Webhook(id: "9F2C", name: "#ai-quota", channel: .slack, scope: .everyLogin,
                               sends: Webhook.Sends(quotaAlerts: true, statusAlerts: false), isOn: true,
                               host: "hooks.slack.com", delivery: .sent(at: Date()))
    private let script = Webhook(id: "7A11", name: "pause-jobs", channel: .json, scope: .provider("claude"),
                                 sends: Webhook.Sends(quotaAlerts: false, statusAlerts: false, recap: true,
                                                      signedOutAlerts: true),
                                 isOn: false)

    @Test func `should have no webhooks until the person adds one`() {
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(repository().webhooks().isEmpty)
    }

    @Test func `should remember webhooks across restarts, without their host or last delivery`() {
        defer { try? FileManager.default.removeItem(at: directory) }
        repository().setWebhooks([team, script])

        let relaunched = repository().webhooks()

        #expect(relaunched.map(\.id) == ["9F2C", "7A11"])
        #expect(relaunched.first == Webhook(id: "9F2C", name: "#ai-quota", channel: .slack, scope: .everyLogin,
                                            sends: Webhook.Sends(quotaAlerts: true, statusAlerts: false), isOn: true))
        #expect(relaunched.last == script)
    }

    @Test func `should save a webhook under alerts.webhooks, every login as a null provider`() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = repository()
        repository.setQuotaAlertPercents([35])
        repository.setWebhooks([team])

        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let alerts = try #require(json["alerts"] as? [String: Any])
        let saved = try #require((alerts["webhooks"] as? [[String: Any]])?.first)

        #expect(alerts["thresholds"] as? [Int] == [35])
        #expect(saved["id"] as? String == "9F2C")
        #expect(saved["name"] as? String == "#ai-quota")
        #expect(saved["channel"] as? String == "slack")
        #expect(saved["provider"] is NSNull)
        #expect(saved["quotaAlerts"] as? Bool == true)
        #expect(saved["statusAlerts"] as? Bool == false)
        #expect(saved["recap"] as? Bool == false)
        #expect(saved["signedOutAlerts"] as? Bool == false)
        #expect(saved["isOn"] as? Bool == true)
        #expect(Set(saved.keys) == ["id", "name", "channel", "provider", "quotaAlerts", "statusAlerts", "recap",
                                    "signedOutAlerts", "isOn"])
    }

    @Test func `should read an old saved webhook as sending neither of the kinds that came later`() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONSettingsStore(fileURL: file)
        store.write(value: [["id": "1", "name": "before the newer kinds existed", "channel": "slack",
                             "provider": NSNull(), "quotaAlerts": true, "statusAlerts": true, "isOn": true]],
                        key: "alerts.webhooks")

        let saved = try #require(repository().webhooks().first)

        #expect(saved.sends.quotaAlerts)
        #expect(saved.sends.statusAlerts)
        #expect(!saved.sends.recap)
        #expect(!saved.sends.signedOutAlerts)
    }

    @Test func `should skip a saved webhook whose channel it doesn't know`() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONSettingsStore(fileURL: file)
        store.write(value: [["id": "1", "name": "x", "channel": "discord", "provider": NSNull(),
                             "quotaAlerts": true, "statusAlerts": true, "isOn": true]], key: "alerts.webhooks")

        #expect(repository().webhooks().isEmpty)
    }
}
