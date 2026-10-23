import Foundation
import Testing
@testable import Infrastructure
import Domain

/// *Rest when empty*'s one saved value per product, under
/// `providers.<id>.restWhenEmpty` in `settings.json`.
@Suite
struct JSONSettingsRepositoryRestWhenEmptyTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
    private var file: URL { directory.appendingPathComponent("settings.json") }

    private func repository() -> JSONSettingsRepository {
        JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
    }

    @Test func `should have nothing saved until the person asks a product to rest`() {
        #expect(repository().whenEmpty(forProvider: "claude") == nil)
    }

    @Test(arguments: [WhenEmpty.watching, .resting(since: Date(timeIntervalSince1970: 1_761_220_000)), .shownAnyway])
    func `should remember where a product is across a relaunch`(state: WhenEmpty) {
        repository().setWhenEmpty(state, forProvider: "claude")

        #expect(repository().whenEmpty(forProvider: "claude") == state)
    }

    @Test func `should save it beside the product's other switches without touching its own`() throws {
        let saved = repository()
        saved.setEnabled(true, forProvider: "claude")

        saved.setWhenEmpty(.resting(since: Date(timeIntervalSince1970: 1_761_220_000)), forProvider: "claude")

        let store = JSONSettingsStore(fileURL: file)
        let value: [String: Any] = try #require(store.read(key: "providers.claude.restWhenEmpty"))
        #expect(value["state"] as? String == "resting")
        #expect(value["since"] as? Double == 1_761_220_000)
        #expect(saved.isEnabled(forProvider: "claude"))
    }

    @Test func `should forget it when the person turns the card off`() {
        repository().setWhenEmpty(.watching, forProvider: "claude")

        repository().setWhenEmpty(nil, forProvider: "claude")

        #expect(repository().whenEmpty(forProvider: "claude") == nil)
    }
}
