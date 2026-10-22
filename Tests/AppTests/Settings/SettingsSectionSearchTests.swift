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

    @Test(arguments: ["mcp", "model context protocol", "localhost", "127.0.0.1"])
    func `should find Local API when the person searches for the MCP server`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.localAPI))
    }
}

extension SettingsSectionSearchTests {
    @Test(arguments: ["webhook", "slack", "json"])
    func `should find Sync & Alerts when the person searches for webhooks`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.syncAlerts))
    }
}
