import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Tests for the Notify! section of JSONSettingsRepository.
@Suite("JSONSettingsRepository Notify Settings Tests")
struct NotifySettingsRepositoryTests {

    static let deviceId = "ABC12345"
    static let token = "sekret-token-42"

    /// Everything one test needs: the repository under test, the throwaway settings file it
    /// writes, and the UserDefaults backed credential store standing in for the Keychain the way
    /// the other settings suites do it.
    ///
    /// The settings file URL and the secure store are both exposed because the token tests have to
    /// look at both halves: the point of the Notify! token living in the credential store is that
    /// it is nowhere near `settings.json`, and that can only be shown by reading the file back.
    private struct Fixture {
        let repository: JSONSettingsRepository
        let secureCredentials: UserDefaultsCredentialRepository
        let settingsURL: URL
        let directory: URL
        let credentials: UserDefaults
        let credentialSuiteName: String
        let secureDefaults: UserDefaults
        let secureSuiteName: String
    }

    /// A credential store that accepts every call and keeps nothing, which is how the Keychain
    /// behaves for a locally built ClaudeBar: the app is ad-hoc signed, so it has no stable
    /// identity for an item's access control to name, and reads and writes alike come back
    /// errSecAuthFailed. `CredentialRepository` has no way to report that, so a refusal and a
    /// success are indistinguishable to the caller, which is exactly the situation under test.
    private final class RefusingCredentialRepository: CredentialRepository, @unchecked Sendable {
        func save(_ value: String, forKey key: String) {}
        func get(forKey key: String) -> String? { nil }
        @discardableResult
        func delete(forKey key: String) -> Bool { true }
        func exists(forKey key: String) -> Bool { false }
    }

    /// The same fixture, but with a secure store that silently drops everything.
    private func makeRefusedFixture() -> (repository: JSONSettingsRepository, settingsURL: URL, credentials: UserDefaults, suiteName: String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notify-refused-test-\(UUID().uuidString)")
        let settingsURL = directory.appendingPathComponent("settings.json")
        let suiteName = "NotifyRefusedTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: suiteName)!
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials,
            secureCredentials: RefusingCredentialRepository()
        )
        return (repository, settingsURL, credentials, suiteName)
    }

    private func makeFixture() -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notify-settings-test-\(UUID().uuidString)")
        let settingsURL = directory.appendingPathComponent("settings.json")
        let credentialSuiteName = "NotifySettingsTests.\(UUID().uuidString)"
        let secureSuiteName = "NotifySettingsSecureTests.\(UUID().uuidString)"
        let credentials = UserDefaults(suiteName: credentialSuiteName)!
        let secureDefaults = UserDefaults(suiteName: secureSuiteName)!
        let secureCredentials = UserDefaultsCredentialRepository(defaults: secureDefaults)
        let repository = JSONSettingsRepository(
            store: JSONSettingsStore(fileURL: settingsURL),
            credentials: credentials,
            secureCredentials: secureCredentials
        )
        return Fixture(
            repository: repository,
            secureCredentials: secureCredentials,
            settingsURL: settingsURL,
            directory: directory,
            credentials: credentials,
            credentialSuiteName: credentialSuiteName,
            secureDefaults: secureDefaults,
            secureSuiteName: secureSuiteName
        )
    }

    private func cleanup(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.directory)
        fixture.credentials.removePersistentDomain(forName: fixture.credentialSuiteName)
        fixture.secureDefaults.removePersistentDomain(forName: fixture.secureSuiteName)
    }

    // MARK: - Defaults

    @Test
    func `should keep Notify! off until the person turns it on`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // The feature sends quota data to a third party service, so it can never start out on.
        #expect(fixture.repository.isNotifyEnabled() == NotifyConstants.defaultEnabled)
        #expect(fixture.repository.isNotifyEnabled() == false)
    }

    @Test
    func `should show the Lock Screen tile and the widget once Notify! is linked, unless turned off`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // A user who linked a device wants to see their quota, and each surface switches off
        // separately once they do not.
        #expect(fixture.repository.isNotifyLiveActivityEnabled() == true)
        #expect(fixture.repository.isNotifyWidgetEnabled() == true)
    }

    @Test
    func `should show the Home Screen tile once Notify! is linked, unless turned off`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // On even though the gateway ships this surface behind a kill switch, because a 503 is
        // handled as "not yet" rather than as an error. Defaulting it off would mean nobody saw
        // the surface on the day it was switched on.
        #expect(fixture.repository.isNotifyScreenWidgetEnabled() == NotifyConstants.defaultScreenWidgetEnabled)
        #expect(fixture.repository.isNotifyScreenWidgetEnabled() == true)
    }

    @Test
    func `should have no linked phone to begin with`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        #expect(fixture.repository.notifyDeviceId() == "")
    }

    @Test
    func `should choose no gauge quota to begin with`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // Empty is how "whichever quota needs attention most" is spelled.
        #expect(fixture.repository.notifyGaugeProviderId() == "")
        #expect(fixture.repository.notifyGaugeQuotaKey() == "")
    }

    @Test
    func `should know of no Lock Screen tile or widget to begin with`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        #expect(fixture.repository.notifyActivityId() == nil)
        #expect(fixture.repository.notifyWidgetId() == nil)
    }

    @Test
    func `should have no Notify! token to begin with`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        #expect(fixture.repository.notifyDeviceToken() == nil)
        #expect(fixture.repository.hasNotifyDeviceToken() == false)
    }

    // MARK: - Setters

    @Test
    func `should remember Notify! turned on`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyEnabled(true)
        #expect(fixture.repository.isNotifyEnabled() == true)
    }

    @Test
    func `should remember the linked phone`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyDeviceId(Self.deviceId)
        #expect(fixture.repository.notifyDeviceId() == Self.deviceId)
    }

    @Test
    func `should remember the Lock Screen tile turned off`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyLiveActivityEnabled(false)
        #expect(fixture.repository.isNotifyLiveActivityEnabled() == false)
    }

    @Test
    func `should remember the widget turned off`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyWidgetEnabled(false)
        #expect(fixture.repository.isNotifyWidgetEnabled() == false)
    }

    @Test
    func `should remember the Home Screen tile turned off`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyScreenWidgetEnabled(false)
        #expect(fixture.repository.isNotifyScreenWidgetEnabled() == false)
    }

    @Test
    func `should remember the gauge's provider`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyGaugeProviderId("claude")
        #expect(fixture.repository.notifyGaugeProviderId() == "claude")
    }

    @Test
    func `should remember the gauge's quota`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyGaugeQuotaKey("five-hour")
        #expect(fixture.repository.notifyGaugeQuotaKey() == "five-hour")
    }

    @Test
    func `should arrange the tile's row worst first until the reader says otherwise`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        #expect(fixture.repository.notifyTileOrder() == .worstFirst)
    }

    @Test
    func `should remember a fixed arrangement of the tile's row`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyTileOrder(.fixed)
        #expect(fixture.repository.notifyTileOrder() == .fixed)
    }

    @Test
    func `should fall back to the default arrangement for a word it does not know`() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // A settings file written by a newer ClaudeBar still arranges its row.
        try FileManager.default.createDirectory(
            at: fixture.settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let raw = try JSONSerialization.data(withJSONObject: ["notify": ["tileOrder": "someNewArrangement"]])
        try raw.write(to: fixture.settingsURL)

        #expect(fixture.repository.notifyTileOrder() == .worstFirst)
    }

    @Test
    func `should remember the Lock Screen tile it started`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyActivityId("LA7Q2ZKM")
        #expect(fixture.repository.notifyActivityId() == "LA7Q2ZKM")
    }

    @Test
    func `should remember the widget it created`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyWidgetId("WG4H2QZ1")
        #expect(fixture.repository.notifyWidgetId() == "WG4H2QZ1")
    }

    @Test
    func `should remember the Home Screen tile it created`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyScreenWidgetId("SW8N3PQ2")
        #expect(fixture.repository.notifyScreenWidgetId() == "SW8N3PQ2")
    }

    // MARK: - Forgetting a Handle

    @Test
    func `should forget the Lock Screen tile once it is cleared`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyActivityId("LA7Q2ZKM")
        fixture.repository.setNotifyActivityId(nil)

        // Removal rather than an empty string: a stored "" would read back as a handle and send
        // every later update to a tile that no longer exists.
        #expect(fixture.repository.notifyActivityId() == nil)
    }

    @Test
    func `should forget the widget once it is cleared`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyWidgetId("WG4H2QZ1")
        fixture.repository.setNotifyWidgetId(nil)

        #expect(fixture.repository.notifyWidgetId() == nil)
    }

    @Test
    func `should forget the Home Screen tile once it is cleared`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyScreenWidgetId("SW8N3PQ2")
        fixture.repository.setNotifyScreenWidgetId(nil)

        // A screen widget stays on the Home Screen until the user removes it, so a stored "" that
        // read back as a handle would aim every later update at a tile that is not there while the
        // one that is sits frozen on their phone.
        #expect(fixture.repository.notifyScreenWidgetId() == nil)
    }

    // MARK: - Device Token

    @Test
    func `should keep the Notify! token in secure storage`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.saveNotifyDeviceToken(Self.token)

        #expect(fixture.repository.notifyDeviceToken() == Self.token)
        #expect(fixture.repository.hasNotifyDeviceToken() == true)
        #expect(fixture.secureCredentials.get(forKey: CredentialKey.notifyDeviceToken) == Self.token)
    }

    @Test
    func `should trim the spaces and newline a pasted token arrives with`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // Tokens arrive off the clipboard, so they arrive with a stray newline.
        fixture.repository.saveNotifyDeviceToken("  \(Self.token)\n")

        #expect(fixture.repository.notifyDeviceToken() == Self.token)
    }

    @Test
    func `should forget the Notify! token when it is removed`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.saveNotifyDeviceToken(Self.token)

        #expect(fixture.repository.deleteNotifyDeviceToken() == true)
        #expect(fixture.repository.notifyDeviceToken() == nil)
        #expect(fixture.repository.hasNotifyDeviceToken() == false)
    }

    @Test
    func `should unlink when the token is saved blank`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.saveNotifyDeviceToken(Self.token)
        fixture.repository.saveNotifyDeviceToken("")

        // An empty field is the user unlinking, not a request to store a blank secret that would
        // look linked and then fail with a 403.
        #expect(fixture.repository.notifyDeviceToken() == nil)
        #expect(fixture.repository.hasNotifyDeviceToken() == false)
    }

    @Test
    func `should unlink when the token is saved as only whitespace`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.saveNotifyDeviceToken(Self.token)
        fixture.repository.saveNotifyDeviceToken(" \n\t ")

        #expect(fixture.repository.notifyDeviceToken() == nil)
        #expect(fixture.repository.hasNotifyDeviceToken() == false)
    }

    @Test
    func `should never write the Notify! token to settings.json`() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyDeviceId(Self.deviceId)
        fixture.repository.saveNotifyDeviceToken(Self.token)

        let data = try Data(contentsOf: fixture.settingsURL)
        let contents = try #require(String(data: data, encoding: .utf8))

        // The device id being there proves this is the file the repository actually writes, which
        // is what makes the token's absence from it mean something.
        #expect(contents.contains(Self.deviceId))
        #expect(contents.contains(Self.token) == false)
    }

    // MARK: - Device Link

    @Test
    func `should have no link to the phone until a token is saved`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyDeviceId(Self.deviceId)

        #expect(fixture.repository.notifyDeviceLink() == nil)
    }

    @Test
    func `should have no link to the phone when its id is malformed`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        // Too short to be a gateway device id, which is the only check that can be made locally.
        fixture.repository.setNotifyDeviceId("ABC1")
        fixture.repository.saveNotifyDeviceToken(Self.token)

        #expect(fixture.repository.notifyDeviceLink() == nil)
    }

    @Test
    func `should link the phone once both its id and token are saved`() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyDeviceId(Self.deviceId)
        fixture.repository.saveNotifyDeviceToken(Self.token)

        let link = try #require(fixture.repository.notifyDeviceLink())
        #expect(link.deviceId == Self.deviceId)
        #expect(link.token == Self.token)
    }

    // MARK: - Gauge Selection

    @Test
    func `should pick the gauge quota automatically when no provider is chosen`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyGaugeQuotaKey("five-hour")

        // Half a selection cannot name a window, so it falls back to whichever quota needs
        // attention most.
        #expect(fixture.repository.notifyGaugeSelection().isAutomatic == true)
    }

    @Test
    func `should pick the gauge quota automatically when no quota is chosen`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyGaugeProviderId("claude")

        #expect(fixture.repository.notifyGaugeSelection().isAutomatic == true)
    }

    @Test
    func `should show the chosen quota on the gauge when provider and quota are both chosen`() {
        let fixture = makeFixture()
        defer { cleanup(fixture) }

        fixture.repository.setNotifyGaugeProviderId("claude")
        fixture.repository.setNotifyGaugeQuotaKey("five-hour")

        let selection = fixture.repository.notifyGaugeSelection()
        #expect(selection.isAutomatic == false)
        #expect(selection == NotifyGaugeSelection(providerId: "claude", quotaKey: "five-hour"))
    }

    // MARK: - When the Keychain refuses

    @Test
    func `should still keep the Notify! token when the Keychain refuses it`() throws {
        // Given a secure store that drops everything, which is what a locally built ClaudeBar
        // actually has: the user presses Save and, without this fallback, nothing is kept and
        // nothing says so.
        let fixture = makeRefusedFixture()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: fixture.suiteName)
            try? FileManager.default.removeItem(at: fixture.settingsURL.deletingLastPathComponent())
        }

        // When
        fixture.repository.saveNotifyDeviceToken(Self.token)

        // Then the link is usable rather than silently empty
        #expect(fixture.repository.notifyDeviceToken() == Self.token)
        #expect(fixture.repository.hasNotifyDeviceToken())
    }

    @Test
    func `should say the Notify! token is not secure when the Keychain refuses it`() throws {
        let fixture = makeRefusedFixture()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: fixture.suiteName)
            try? FileManager.default.removeItem(at: fixture.settingsURL.deletingLastPathComponent())
        }

        fixture.repository.saveNotifyDeviceToken(Self.token)

        // The pane shows a badge saying the token is on file, and that badge must not be read as
        // "in the Keychain" when it is not.
        #expect(fixture.repository.notifyDeviceTokenIsSecure() == false)
    }

    @Test
    func `should never write the Notify! token to settings.json when the Keychain refuses it`() throws {
        let fixture = makeRefusedFixture()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: fixture.suiteName)
            try? FileManager.default.removeItem(at: fixture.settingsURL.deletingLastPathComponent())
        }

        fixture.repository.setNotifyDeviceId(Self.deviceId)
        fixture.repository.saveNotifyDeviceToken(Self.token)

        // The fallback is the app's credential defaults, never the settings JSON. Losing the
        // Keychain must not turn the token into a line in a file the user might paste into an
        // issue report.
        let contents = try String(contentsOf: fixture.settingsURL, encoding: .utf8)
        #expect(contents.contains(Self.token) == false)
        #expect(contents.contains(Self.deviceId))
    }

    @Test
    func `should forget the Notify! token from the fallback store when the Keychain refused it`() throws {
        let fixture = makeRefusedFixture()
        defer {
            UserDefaults.standard.removePersistentDomain(forName: fixture.suiteName)
            try? FileManager.default.removeItem(at: fixture.settingsURL.deletingLastPathComponent())
        }

        fixture.repository.saveNotifyDeviceToken(Self.token)

        // When
        fixture.repository.deleteNotifyDeviceToken()

        // Then: removing a link has to remove it, wherever it ended up
        #expect(fixture.repository.notifyDeviceToken() == nil)
        #expect(fixture.repository.hasNotifyDeviceToken() == false)
    }


    // MARK: - Saving a link

    @Test
    func `should keep the tile and widgets already on the phone when the same phone is saved again`() throws {
        // Given a linked device with all three surfaces published
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        fixture.repository.saveNotifyDeviceLink(try #require(NotifyDeviceLink(deviceId: Self.deviceId, token: Self.token)))
        fixture.repository.setNotifyActivityId("LA7Q2ZKM")
        fixture.repository.setNotifyWidgetId("WG4H2QZ1")
        fixture.repository.setNotifyScreenWidgetId("SW3K9QZ2")

        // When the user presses Save again, which the pane allows, with a
        // rotated token but the same phone
        fixture.repository.saveNotifyDeviceLink(try #require(NotifyDeviceLink(deviceId: Self.deviceId, token: "a-rotated-token")))

        // Then the handles survive. Clearing them would orphan a tile and two
        // widgets that are still ours and make the next publish build a second
        // set beside them, which on a Home Screen is a duplicate the user has to
        // go and remove by hand.
        #expect(fixture.repository.notifyActivityId() == "LA7Q2ZKM")
        #expect(fixture.repository.notifyWidgetId() == "WG4H2QZ1")
        #expect(fixture.repository.notifyScreenWidgetId() == "SW3K9QZ2")
        #expect(fixture.repository.notifyDeviceToken() == "a-rotated-token")
    }

    @Test
    func `should forget the previous phone's tile and widgets when a different phone is linked`() throws {
        let fixture = makeFixture()
        defer { cleanup(fixture) }
        fixture.repository.saveNotifyDeviceLink(try #require(NotifyDeviceLink(deviceId: Self.deviceId, token: Self.token)))
        fixture.repository.setNotifyActivityId("LA7Q2ZKM")
        fixture.repository.setNotifyWidgetId("WG4H2QZ1")
        fixture.repository.setNotifyScreenWidgetId("SW3K9QZ2")

        // When a different phone is linked
        fixture.repository.saveNotifyDeviceLink(try #require(NotifyDeviceLink(deviceId: "ZZZ99999", token: Self.token)))

        // Then the handles go, because they name surfaces on a phone this link
        // can no longer write to, and keeping them would spend a 403 finding out
        #expect(fixture.repository.notifyActivityId() == nil)
        #expect(fixture.repository.notifyWidgetId() == nil)
        #expect(fixture.repository.notifyScreenWidgetId() == nil)
        #expect(fixture.repository.notifyDeviceId() == "ZZZ99999")
    }

}
