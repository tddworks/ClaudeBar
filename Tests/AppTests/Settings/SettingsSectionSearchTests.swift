import Testing
@testable import ClaudeBar

@Suite
struct SettingsSectionSearchTests {
    @Test(arguments: ["native", "icon", "monochrome", "grayscale"])
    func `icon searches include appearance settings`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.appearance))
    }

    @Test(arguments: ["email", "account", "label"])
    func `account label searches include menu bar settings`(query: String) {
        #expect(SettingsSection.matching(filter: query).contains(.menuBar))
    }
}
