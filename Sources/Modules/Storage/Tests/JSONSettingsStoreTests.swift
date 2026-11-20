import Testing
import Foundation
import Quotas
import DataSources
import Providers
import Monitoring
import Leaderboard
import Activity
import Alerting
import LocalAPI
@testable import Storage

@Suite("JSONSettingsStore Tests")
struct JSONSettingsStoreTests {

    private func makeStore(initialJSON: String? = nil) throws -> (JSONSettingsStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileURL = tempDir.appendingPathComponent("settings.json")
        if let json = initialJSON {
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let store = JSONSettingsStore(fileURL: fileURL)
        return (store, tempDir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Flat Key Read/Write

    @Test
    func `should have no settings when settings.json does not exist`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        let value: String? = store.read(key: "someKey")
        #expect(value == nil)
    }

    @Test
    func `should create settings.json and keep the value written`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: "hello", key: "greeting")

        let result: String? = store.read(key: "greeting")
        #expect(result == "hello")
    }

    @Test
    func `should keep the other settings when one is written`() throws {
        let json = """
        {
            "existing": "value"
        }
        """
        let (store, dir) = try makeStore(initialJSON: json)
        defer { cleanup(dir) }

        store.write(value: "new", key: "added")

        let existing: String? = store.read(key: "existing")
        let added: String? = store.read(key: "added")
        #expect(existing == "value")
        #expect(added == "new")
    }

    @Test
    func `should forget a setting written as nothing`() throws {
        let json = """
        {
            "toRemove": "goodbye"
        }
        """
        let (store, dir) = try makeStore(initialJSON: json)
        defer { cleanup(dir) }

        store.write(value: nil, key: "toRemove")

        let result: String? = store.read(key: "toRemove")
        #expect(result == nil)
    }

    // MARK: - Nested Key (Dot-Notation) Read/Write

    @Test
    func `should find a setting nested in settings.json by its dotted name`() throws {
        let json = """
        {
            "app": {
                "themeMode": "dark"
            }
        }
        """
        let (store, dir) = try makeStore(initialJSON: json)
        defer { cleanup(dir) }

        let result: String? = store.read(key: "app.themeMode")
        #expect(result == "dark")
    }

    @Test
    func `should create the sections a nested setting needs`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: "cli", key: "claude.probeMode")

        let result: String? = store.read(key: "claude.probeMode")
        #expect(result == "cli")
    }

    @Test
    func `should keep a nested setting's neighbours when it changes`() throws {
        let json = """
        {
            "app": {
                "themeMode": "dark",
                "overviewMode": true
            }
        }
        """
        let (store, dir) = try makeStore(initialJSON: json)
        defer { cleanup(dir) }

        store.write(value: "light", key: "app.themeMode")

        let theme: String? = store.read(key: "app.themeMode")
        let overview: Bool? = store.read(key: "app.overviewMode")
        #expect(theme == "light")
        #expect(overview == true)
    }

    @Test
    func `should keep a setting nested three levels deep`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: true, key: "providers.claude.isEnabled")

        let result: Bool? = store.read(key: "providers.claude.isEnabled")
        #expect(result == true)
    }

    // MARK: - Type Support

    @Test
    func `should keep a yes or no setting`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: false, key: "app.enabled")

        let result: Bool? = store.read(key: "app.enabled")
        #expect(result == false)
    }

    @Test
    func `should keep a whole-number setting`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: 42, key: "port")

        let result: Int? = store.read(key: "port")
        #expect(result == 42)
    }

    @Test
    func `should keep a decimal setting`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: 3.14, key: "budget")

        let result: Double? = store.read(key: "budget")
        #expect(result == 3.14)
    }

    @Test
    func `should keep a list setting`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        store.write(value: ["us-east-1", "eu-west-1"], key: "bedrock.regions")

        let result: [String]? = store.read(key: "bedrock.regions")
        #expect(result == ["us-east-1", "eu-west-1"])
    }

    // MARK: - Persistence

    @Test
    func `should keep settings across restarts`() throws {
        let (store1, dir) = try makeStore()
        defer { cleanup(dir) }

        store1.write(value: "persisted", key: "app.test")

        let store2 = JSONSettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        let result: String? = store2.read(key: "app.test")
        #expect(result == "persisted")
    }

    // MARK: - Resilience

    @Test
    func `should have no settings when settings.json is broken`() throws {
        let (store, dir) = try makeStore(initialJSON: "not valid json {{{")
        defer { cleanup(dir) }

        let result: String? = store.read(key: "anything")
        #expect(result == nil)
    }

    @Test
    func `should replace a broken settings.json with a readable one when writing`() throws {
        let (store, dir) = try makeStore(initialJSON: "broken")
        defer { cleanup(dir) }

        store.write(value: "fixed", key: "status")

        let result: String? = store.read(key: "status")
        #expect(result == "fixed")
    }

    @Test
    func `should create the folders settings.json lives in`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let deepPath = tempDir
            .appendingPathComponent("nested")
            .appendingPathComponent("dir")
            .appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = JSONSettingsStore(fileURL: deepPath)
        store.write(value: "created", key: "test")

        let result: String? = store.read(key: "test")
        #expect(result == "created")
    }

    // MARK: - readAll

    @Test
    func `should give back every setting in the file`() throws {
        let json = """
        {
            "app": { "theme": "dark" },
            "version": 1
        }
        """
        let (store, dir) = try makeStore(initialJSON: json)
        defer { cleanup(dir) }

        let all = store.readAll()
        #expect(all["version"] as? Int == 1)
        #expect((all["app"] as? [String: Any])?["theme"] as? String == "dark")
    }

    @Test
    func `should give back no settings when there is no file`() throws {
        let (store, dir) = try makeStore()
        defer { cleanup(dir) }

        let all = store.readAll()
        #expect(all.isEmpty)
    }
}
