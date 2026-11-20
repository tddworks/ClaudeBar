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

/// A provider-scope setting's value lives at `<id>.<setting>` — today's keys,
/// so a region chosen before the form was data is read as it was.
@Suite
struct JSONSettingsRepositorySettingValueTests {
    private func make() -> (JSONSettingsStore, JSONSettingsRepository, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        return (store, JSONSettingsRepository(store: store), directory)
    }

    @Test
    func `should remember a provider's setting under the provider and setting name`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }

        repository.setValue("international", "region", forProvider: "acme")

        #expect(repository.value("region", forProvider: "acme") == "international")
        #expect(store.read(key: "acme.region") as String? == "international")
    }

    @Test
    func `should keep a region chosen before settings were data`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.write(value: "international", key: "kimi.region")

        #expect(repository.value("region", forProvider: "kimi") == "international")
    }

    @Test
    func `should fall back to the setting's default once its value is forgotten`() {
        let (_, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        repository.setValue("international", "region", forProvider: "acme")

        repository.setValue(nil, "region", forProvider: "acme")

        #expect(repository.value("region", forProvider: "acme") == nil)
    }

    @Test
    func `should keep a value an old card saved under another name, and move it when changed`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.write(value: "MY_GATEWAY_KEY", key: "vercel.authEnvVar")

        #expect(repository.value("authEnvVar", forProvider: "vercel-gateway") == "MY_GATEWAY_KEY")

        repository.setValue("OTHER_KEY", "authEnvVar", forProvider: "vercel-gateway")
        #expect(store.read(key: "vercel-gateway.authEnvVar") as String? == "OTHER_KEY")
        #expect(store.read(key: "vercel.authEnvVar") as String? == nil)
    }

    @Test
    func `should show a list an old card saved as comma-separated text`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.write(value: ["us-east-1", "eu-west-1"], key: "bedrock.regions")

        #expect(repository.value("regions", forProvider: "bedrock") == "us-east-1, eu-west-1")
    }

    @Test
    func `should show a number an old card saved as text`() {
        let (store, repository, directory) = make()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.write(value: 300, key: "copilot.monthlyLimit")

        #expect(repository.value("monthlyLimit", forProvider: "copilot") == "300")
    }

    @Test
    func `should keep a value an old card saved in UserDefaults, and move it to settings.json when changed`() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let defaults = UserDefaults(suiteName: "claudebar-test-\(UUID().uuidString)")!
        defaults.set("octocat", forKey: "com.claudebar.credentials.github-username")
        let repository = JSONSettingsRepository(store: store, credentials: defaults)

        #expect(repository.value("username", forProvider: "copilot") == "octocat")

        repository.setValue("hubot", "username", forProvider: "copilot")
        #expect(store.read(key: "copilot.username") as String? == "hubot")
        #expect(defaults.string(forKey: "com.claudebar.credentials.github-username") == nil)
    }
}
