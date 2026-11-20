#if os(macOS)
import Foundation
import Testing
import Quotas
import DataSources
@testable import Providers

/// What *In use*'s shell lines do when the Mac's own zsh and bash source
/// them: each `claude` / `codex` starts on the folder chosen in ClaudeBar.
@Suite(.serialized)
struct ShellSetupInRealShellsTests {
    private let home: URL
    private let setup: ShellSetup

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("shell-setup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setup = ShellSetup(commands: [
            TerminalCommand(name: "claude", environment: ["CLAUDE_CONFIG_DIR": "{{account.folder}}"]),
            TerminalCommand(name: "codex", environment: ["CODEX_HOME": "{{account.folder}}"]),
        ], home: home)
    }

    @Test(arguments: [LoginShell.zsh, .bash])
    func `should start a new session on the folder chosen in ClaudeBar`(shell: LoginShell) throws {
        try setup.install(shell)
        try record("claude", "/Users/you/.claude-work")

        #expect(try run(shell, "claude") == "CLAUDE_CONFIG_DIR=/Users/you/.claude-work args=--version")
    }

    @Test(arguments: [LoginShell.zsh, .bash])
    func `should run the CLI as it always did when nothing is chosen`(shell: LoginShell) throws {
        try setup.install(shell)

        #expect(try run(shell, "claude") == "CLAUDE_CONFIG_DIR= args=--version")
        #expect(try run(shell, "codex", environment: ["CODEX_HOME": "/mine"]) == "CODEX_HOME=/mine args=--version")
    }

    @Test(arguments: [LoginShell.zsh, .bash])
    func `should still run the aliased program on the chosen folder when the CLI has an alias`(shell: LoginShell) throws {
        let program = try fakeCLI("claude", in: "local")
        try write(shell == .zsh ? ".zshrc" : ".bash_profile", "alias claude=\"\(program.path)\"\n")
        try setup.install(shell)
        try record("claude", "/Users/you/.claude-work")

        #expect(try run(shell, "claude", path: false) == "CLAUDE_CONFIG_DIR=/Users/you/.claude-work args=--version")
    }

    // MARK: - Helpers

    private func write(_ name: String, _ text: String) throws {
        let url = home.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func record(_ providerId: String, _ folder: String) throws {
        try write(".claudebar/in-use/\(providerId)", folder)
    }

    /// A stand-in CLI that prints the variable it was started with.
    @discardableResult
    private func fakeCLI(_ name: String, in folder: String = "bin") throws -> URL {
        let variable = name == "claude" ? "CLAUDE_CONFIG_DIR" : "CODEX_HOME"
        let url = home.appendingPathComponent("\(folder)/\(name)")
        try write("\(folder)/\(name)", "#!/bin/sh\necho \"\(variable)=$\(variable) args=$*\"\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Runs `<command> --version` in `shell` with the installed file sourced,
    /// as an interactive session would.
    private func run(_ shell: LoginShell, _ command: String, environment: [String: String] = [:], path: Bool = true) throws -> String {
        if path { try fakeCLI(command) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell == .zsh ? "/bin/zsh" : "/bin/bash")
        let file = setup.file(for: shell).path
        let script = shell == .bash ? "shopt -s expand_aliases; . '\(file)'\n\(command) --version" : ". '\(file)'\n\(command) --version"
        process.arguments = ["-f", "-c", script].filter { shell == .zsh || $0 != "-f" }
        process.environment = ["HOME": home.path, "PATH": home.appendingPathComponent("bin").path + ":/usr/bin:/bin"]
            .merging(environment) { _, given in given }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
