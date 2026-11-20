import Foundation
import Testing
import Quotas
import DataSources
import Providers
import Monitoring
import Leaderboard
import Activity
import Alerting
import LocalAPI
@testable import Storage

/// The person's quota-alert percentages, kept in `settings.json`.
@Suite
struct JSONSettingsRepositoryQuotaAlertTests {
    @Test func `should have no quota alert percentages until the person adds one`() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONSettingsRepository(store: JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json")))

        #expect(repository.quotaAlertPercents().isEmpty)
    }

    @Test func `should remember quota alert percentages across restarts`() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        JSONSettingsRepository(store: JSONSettingsStore(fileURL: file)).setQuotaAlertPercents([60, 35])

        let relaunched = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))

        #expect(relaunched.quotaAlertPercents() == [60, 35])
    }
}
