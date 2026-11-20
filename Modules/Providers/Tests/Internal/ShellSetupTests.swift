import Foundation
import Testing
import Quotas
import DataSources
@testable import Providers

/// The shell lines behind *In use*: each `claude` / `codex` reads the login
/// chosen in ClaudeBar and starts on its folder. Written once between
/// markers, removable without touching anything else in the file.
@Suite(.serialized)
struct ShellSetupTests {
    private let home: URL
    private let setup: ShellSetup

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("shell-setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setup = ShellSetup(commands: [
            TerminalCommand(name: "claude", environment: ["CLAUDE_CONFIG_DIR": "{{account.folder}}"]),
            TerminalCommand(name: "codex", environment: ["CODEX_HOME": "{{account.folder}}"]),
            // A second product on the same CLI: wrapped once all the same.
            TerminalCommand(name: "claude", environment: ["CLAUDE_CONFIG_DIR": "{{account.folder}}"]),
        ], home: home)
    }

    // MARK: - Where

    @Test
    func `should write each shell's lines to that shell's own startup file`() {
        #expect(setup.file(for: .zsh).path == home.appendingPathComponent(".zshrc").path)
        #expect(setup.file(for: .bash).path == home.appendingPathComponent(".bash_profile").path)
        #expect(setup.file(for: .fish).path == home.appendingPathComponent(".config/fish/conf.d/claudebar-in-use.fish").path)
    }

    @Test
    func `should set up the person's login shell, zsh when it is unknown`() {
        #expect(LoginShell.login("/bin/bash") == .bash)
        #expect(LoginShell.login("/opt/homebrew/bin/fish") == .fish)
        #expect(LoginShell.login("/bin/zsh") == .zsh)
        #expect(LoginShell.login(nil) == .zsh)
    }

    @Test
    func `should wrap a CLI once however many products run it`() {
        let lines = setup.lines(for: .zsh)

        #expect(lines.components(separatedBy: "function claude {").count == 2)
        #expect(lines.contains("# ClaudeBar → In use: new claude and codex sessions"))
    }

    // MARK: - Install and remove

    @Test
    func `should add one block and keep the rest of the file however often it is installed`() throws {
        try write(".zshrc", "export PATH=\"$HOME/bin:$PATH\"\n")

        try setup.install(.zsh)
        try setup.install(.zsh)

        let text = try read(".zshrc")
        #expect(text.hasPrefix("export PATH=\"$HOME/bin:$PATH\"\n"))
        #expect(text.components(separatedBy: ShellSetup.begin).count == 2)
        #expect(setup.isInstalled(.zsh))
    }

    @Test
    func `should create the startup file when there is none`() throws {
        try setup.install(.zsh)

        #expect(setup.isInstalled(.zsh))
    }

    @Test
    func `should take out only ClaudeBar's block when removed`() throws {
        try write(".zshrc", "alias ll='ls -l'\n")
        try setup.install(.zsh)
        try append(".zshrc", "export EDITOR=vim\n")

        try setup.remove(.zsh)

        #expect(try read(".zshrc") == "alias ll='ls -l'\nexport EDITOR=vim\n")
        #expect(!setup.isInstalled(.zsh))
    }

    @Test
    func `should give fish a file of its own and delete it when removed`() throws {
        try setup.install(.fish)
        #expect(setup.isInstalled(.fish))
        #expect(try read(".config/fish/conf.d/claudebar-in-use.fish").contains("function claude"))

        try setup.remove(.fish)

        #expect(!FileManager.default.fileExists(atPath: setup.file(for: .fish).path))
    }

    // MARK: - Helpers

    private func write(_ name: String, _ text: String) throws {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func append(_ name: String, _ text: String) throws {
        try write(name, try read(name) + text)
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: home.appendingPathComponent(name), encoding: .utf8)
    }
}
