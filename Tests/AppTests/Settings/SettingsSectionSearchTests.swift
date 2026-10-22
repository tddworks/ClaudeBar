import Testing
@testable import ClaudeBar

@Suite
struct SettingsSectionSearchTests {
    @Test(arguments: ["native", "icon", "monochrome", "grayscale"])
    func `should find Appearance when the person searches for icons`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.appearance))
    }

    @Test(arguments: ["email", "account", "label"])
    func `should find Menu Bar when the person searches for account labels`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.menuBar))
    }
}

extension SettingsSectionSearchTests {
    @Test(arguments: ["webhook", "slack", "json"])
    func `should find Sync & Alerts when the person searches for webhooks`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.syncAlerts))
    }
}
