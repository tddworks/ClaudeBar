import Testing
import Foundation
import DataSources
@testable import Providers

/// In use's shell lines as the App gets them: one wrapper for each command a
/// definition declares.
@Suite
struct ShellLinesFactoryTests {
    @Test
    func `should wrap each declared command in the lines it writes`() {
        let lines = ProviderFactory.makeShellLines(commands: [
            TerminalCommand(name: "claude", environment: ["CLAUDE_CONFIG_DIR": "{{account.folder}}"]),
        ])

        #expect(lines.lines(for: .zsh).contains("claude"))
    }
}
