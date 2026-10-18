@testable import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// JetBrains AI as data: the AI quota a JetBrains IDE saves on this computer, from
/// the IDE used last, read by `jetbrains-quota.js`.
@MainActor @Suite
struct JetBrainsDefinitionTests {
    /// The quota file as an IDE writes it: JSON inside HTML-encoded XML attributes.
    static func quota(current: String = "7478.3", maximum: String = "1000000", next: String? = "2026-11-01T14:00:54.939Z") -> String {
        func encoded(_ json: String) -> String {
            json.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "\n", with: "&#10;")
        }
        let info = """
        {
          "type": "Available",
          "current": "\(current)",
          "maximum": "\(maximum)",
          "until": "2026-11-09T21:00:00Z",
          "tariffQuota": { "current": "\(current)", "maximum": "\(maximum)", "available": "0" }
        }
        """
        let refill = next.map { """
        {
          "type": "Known",
          "next": "\($0)",
          "tariff": { "amount": "\(maximum)", "duration": "PT720H" }
        }
        """ }
        return """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="quotaInfo" value="\(encoded(info))" />
            \(refill.map { "<option name=\"nextRefill\" value=\"\(encoded($0))\" />" } ?? "")
          </component>
        </application>
        """
    }

    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// A quota file in one IDE's folder, last changed `ago` seconds before now.
    private func ide(_ folder: String, _ xml: String, ago: TimeInterval = 0) throws {
        let file = home.appendingPathComponent("Library/Application Support/\(folder)/options/AIAssistantQuotaManager2.xml")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(xml.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ago)], ofItemAtPath: file.path)
    }

    private func make() throws -> Provider {
        let definition = try ProviderFactory.builtIn("jetbrains")
        let folder = home
        var platform = Platform.current
        platform.applicationData = { home, _ in home.appendingPathComponent("Library/Application Support") }
        let fixturePlatform = platform
        return Provider(definition: definition, settings: InMemoryProviderSettings(), makeDataSource: { source, _ in
            DataSources.make(source, providerId: definition.id, platform: fixturePlatform, network: MockNetworkClient(),
                             scripts: ProviderFactory.builtInScripts, environment: { _ in nil },
                             homeDirectory: folder, now: { Date() })
        })
    }

    @Test
    func `should be JetBrains AI, off until turned on, reading only local files`() throws {
        let jetbrains = try make()
        #expect(jetbrains.id == "jetbrains")
        #expect(jetbrains.name == "JetBrains AI")
        #expect(jetbrains.plainIsInLineup == false)
        let source = try #require(jetbrains.definition.dataSources.first)
        #expect(source.fetch.connection.urls.isEmpty)
        #expect(source.fetch.connection.commands.isEmpty)
    }

    @Test
    func `should show the AI credits left this month and when they refill`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try ide("JetBrains/IntelliJIdea2025.3", Self.quota(current: "250000", maximum: "1000000"))

        let usage = try await make().refreshPlain()

        let credits = try #require(usage.quotas.first)
        #expect(credits.quotaType == .timeLimit("AI credits"))
        #expect(credits.percentRemaining == 75)
        let refill = try #require(ISO8601DateFormatter().date(from: "2026-11-01T14:00:54Z")).addingTimeInterval(0.939)
        #expect(abs((credits.resetsAt ?? .distantPast).timeIntervalSince(refill)) < 0.001)
        #expect((credits.windowDuration ?? -1) == 2_592_000)
    }

    @Test
    func `should read the IDE used last, Android Studio included`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try ide("JetBrains/IntelliJIdea2025.3", Self.quota(current: "100000"), ago: 3600)
        try ide("JetBrains/PyCharm2025.2", Self.quota(current: "900000"), ago: 86400)
        try ide("Google/AndroidStudio2025.1", Self.quota(current: "500000"), ago: 60)

        let usage = try await make().refreshPlain()

        #expect(usage.quotas.first?.percentRemaining == 50)
    }

    @Test
    func `should show the quota with no refill time when the IDE saved none`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try ide("JetBrains/GoLand2025.3", Self.quota(current: "0", next: nil))

        let usage = try await make().refreshPlain()

        #expect(usage.quotas.first?.percentRemaining == 100)
        #expect(usage.quotas.first?.resetsAt == nil)
    }

    @Test
    func `should not be set up when no JetBrains IDE has saved a quota`() async throws {
        let jetbrains = try make()
        #expect(await jetbrains.isAvailable(jetbrains.defaultAccount) == false)
    }

    @Test(arguments: ["<application/>", "not xml at all"])
    func `should fail reading the quota when the IDE's file has none`(_ xml: String) async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try ide("JetBrains/WebStorm2025.3", xml)
        let jetbrains = try make()
        let account = jetbrains.defaultAccount
        await #expect(throws: UsageError.self) { try await jetbrains.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }

    /// How an IDE saves a quota it doesn't know, or failed to get.
    private static func state(_ quota: String) -> String {
        """
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="nextRefill" value="{&#10;  &quot;type&quot;: &quot;Error&quot;,&#10;  &quot;exception&quot;: &quot;&quot;,&#10;  &quot;previous&quot;: null&#10;}" />
            <option name="quotaInfo" value="\(quota)" />
          </component>
        </application>
        """
    }

    @Test
    func `should ask to sign in to JetBrains AI when the IDE knows no quota`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try ide("JetBrains/IntelliJIdea2026.1", Self.state("{&#10;  &quot;type&quot;: &quot;Unknown&quot;&#10;}"))
        let jetbrains = try make()
        await #expect(throws: UsageError.sessionExpired(hint: "Sign in to JetBrains AI in your IDE, then use AI Assistant once.")) {
            try await jetbrains.refresh(jetbrains.defaultAccount)
        }
    }

    @Test
    func `should say the IDE couldn't get the quota when it saved an error`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try ide("JetBrains/IntelliJIdea2025.1", Self.state("{&#10;  &quot;type&quot;: &quot;Error&quot;,&#10;  &quot;exception&quot;: &quot;&quot;&#10;}"))
        let jetbrains = try make()
        await #expect(throws: UsageError.executionFailed("Your JetBrains IDE couldn't get the AI quota. Open AI Assistant in it to try again.")) {
            try await jetbrains.refresh(jetbrains.defaultAccount)
        }
    }

    /// Reads the real definition's XML before mapping, so it needs no JavaScript engine.
    @Test
    func `should read the newest IDE quota from the app data folder supplied to the factory`() async throws {
        let appData = home.appendingPathComponent("Controlled App Data")
        defer { try? FileManager.default.removeItem(at: home) }
        let old = appData.appendingPathComponent("JetBrains/PyCharm2025.2/options/AIAssistantQuotaManager2.xml")
        let newest = appData.appendingPathComponent("Google/AndroidStudio2025.1/options/AIAssistantQuotaManager2.xml")
        for (file, xml, age) in [(old, Self.quota(current: "900000"), 3600.0),
                                  (newest, Self.quota(current: "250000"), 60.0)] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        // A newer quota at the old Mac location must not override the supplied fact.
        try ide("JetBrains/IntelliJIdea2025.3", Self.quota(current: "100000"))
        var platform = Platform.current
        platform.applicationData = { _, _ in appData }
        let definition = try #require(try ProviderFactory.builtIn("jetbrains").dataSources.first)
        let source = DataSources.make(definition, providerId: "jetbrains", platform: platform,
                                     network: MockNetworkClient(), environment: { _ in nil },
                                     homeDirectory: home, now: { Date() })

        #expect(await source.isReady())
        let response = try await source.fetchResponse()
        #expect(response.text == Self.quota(current: "250000"))
    }

    #if os(Windows)
    @Test(arguments: [nil, "", "redirected"] as [String?])
    func `should read the newest IDE quota from Windows app data including redirected APPDATA`(_ appDataValue: String?) async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let appData = appDataValue == "redirected"
            ? home.appendingPathComponent("Redirected App Data")
            : home.appendingPathComponent("AppData/Roaming")
        let environment: @Sendable (String) -> String? = { name in
            guard name == "APPDATA" else { return nil }
            return appDataValue == "redirected" ? appData.path : appDataValue
        }
        let older = appData.appendingPathComponent("JetBrains/IntelliJIdea2025.3/options/AIAssistantQuotaManager2.xml")
        let newest = appData.appendingPathComponent("Google/AndroidStudio2025.1/options/AIAssistantQuotaManager2.xml")
        for (file, xml, age) in [(older, Self.quota(current: "900000"), 3600.0),
                                  (newest, Self.quota(current: "500000"), 60.0)] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        try ide("JetBrains/WebStorm2025.3", Self.quota(current: "100000"))
        let definition = try #require(try ProviderFactory.builtIn("jetbrains").dataSources.first)
        let source = DataSources.make(definition, providerId: "jetbrains", platform: .current,
                                     network: MockNetworkClient(), environment: environment,
                                     homeDirectory: home, now: { Date() })

        #expect(await source.isReady())
        let response = try await source.fetchResponse()
        #expect(response.text == Self.quota(current: "500000"))
    }
    #endif
}
