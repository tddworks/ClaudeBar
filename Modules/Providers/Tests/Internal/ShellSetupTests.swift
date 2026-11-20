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

    // MARK: - What the lines do, run in the real shells

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

    private func append(_ name: String, _ text: String) throws {
        try write(name, try read(name) + text)
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: home.appendingPathComponent(name), encoding: .utf8)
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
