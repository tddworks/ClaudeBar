import Testing
import Foundation
import Domain
import Infrastructure
@testable import ClaudeBar

@Suite @MainActor
struct AppSettingsUsageSectionsTests {
    private let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func load() -> AppSettings {
        AppSettings(repository: JSONSettingsRepository(store: JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json"))))
    }

    @Test func `should remember a usage section the person hides or shows`() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = load()

        settings.setShown(.today, false)
        settings.setShown(.lastYear, true)

        #expect(!load().isShown(.today))
        #expect(load().isShown(.lastYear))
        #expect(load().isShown(.lastThirtyDays))
    }

    @Test func `should not read the year while neither year section is shown`() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = load()

        #expect(!settings.readsTheYear)
    }

    @Test func `should read the year once the model mix is shown`() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = load()

        settings.setShown(.modelMix, true)

        #expect(settings.readsTheYear)
    }
}
