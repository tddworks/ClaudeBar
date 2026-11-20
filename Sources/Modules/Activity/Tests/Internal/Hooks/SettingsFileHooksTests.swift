import Testing
import Foundation
@testable import Activity

/// The Hooks pane's switch: ClaudeBar's hooks in Claude Code's settings file,
/// put in and taken out again.
@Suite
struct SettingsFileHooksTests {
    private let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("hooks-\(UUID().uuidString)/settings.json").path

    @Test
    func `should say the hooks are off until they are put in, and off again once taken out`() throws {
        let hooks = SettingsFileHooks(path: path)
        #expect(!hooks.isInstalled)

        try hooks.install()
        #expect(hooks.isInstalled)

        try hooks.uninstall()
        #expect(!hooks.isInstalled)
    }
}
