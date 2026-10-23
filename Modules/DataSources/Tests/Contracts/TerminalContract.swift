import Foundation
import Quotas
import Testing
@testable import DataSources

/// The Terminal port's contract (MODULAR_DESIGN §10), run against this
/// platform's adapter: a CLI run in a terminal shows the screen a person
/// would see — drawn by a terminal emulator, so its cursor moves and clears
/// land — and a CLI that isn't installed says so. Its CLI is a script that
/// draws the way a TUI does, in a folder whose name has a space, brackets
/// and an ampersand: the characters a path most often breaks on.
@Suite(
    .enabled(if: Platform.current.runCLI != nil && Platform.current.screenRenderer != nil,
             "reads a CLI's screen: \(Platform.current.name) has no terminal yet (phase 5)")
)
struct TerminalContract {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("terminal (x86) & \(UUID().uuidString.prefix(8))", isDirectory: true)

    /// The CLI the contract runs: loading text cleared away, then the usage
    /// line set where the cursor lands.
    private func script() throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("contract-cli.sh")
        try Data("""
        #!/bin/sh
        printf 'Loading quotas...\\033[2J\\033[HCurrent session \\033[5C1%% used\\n'

        """.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    private func executor() throws -> any CLIExecutor {
        let make = try #require(Platform.current.runCLI, "\(Platform.current.name) has no terminal")
        return make(CLICall(cli: "contract-cli"))
    }

    private func render() throws -> (String) -> String {
        try #require(Platform.current.screenRenderer, "\(Platform.current.name) has no screen renderer")
    }

    @Test
    func `should draw the screen a person would see, cursor moves and all`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await executor().execute(
            binary: try script(), args: [], input: "", timeout: 20,
            workingDirectory: nil, autoResponses: [:]
        )
        let screen = try render()(result.output)

        #expect(!screen.contains("\u{1B}"), "the screen a person sees carries no escape codes")
        #expect(screen.contains("Current session      1% used"), "the cursor move lands the text where a terminal puts it")
        #expect(!screen.contains("Loading"), "what the CLI cleared is gone")
    }

    @Test
    func `should say a CLI that isn't installed is not found`() async throws {
        await #expect(throws: UsageError.cliNotFound("claudebar-missing-cli")) {
            try await executor().execute(
                binary: "claudebar-missing-cli", args: [], input: "", timeout: 5,
                workingDirectory: nil, autoResponses: [:]
            )
        }
    }
}
