import Foundation
import Quotas
import Testing
@testable import DataSources

/// The Terminal port's contract (MODULAR_DESIGN §10), run against this
/// platform's adapter: a CLI run in a terminal shows the screen a person
/// would see — drawn by a terminal emulator, so its cursor moves and clears
/// land — a CLI reads what is typed into it, and a CLI that isn't installed
/// says so. Its CLI is a script that draws the way a TUI does (`sh` on POSIX,
/// a `.cmd` on Windows), in a folder whose name has a space, brackets and an
/// ampersand: the characters a path most often breaks on.
@Suite(
    .enabled(if: Platform.current.runCLI != nil && Platform.current.screenRenderer != nil,
             "reads a CLI's screen: \(Platform.current.name) has no terminal yet (phase 5)")
)
struct TerminalContract {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("terminal (x86) & \(UUID().uuidString.prefix(8))", isDirectory: true)

    /// The CLI the contract runs: loading text cleared away, then the usage
    /// line set where the cursor lands.
    private func drawing() throws -> String {
        #if os(Windows)
        try script(named: "contract-cli.cmd", """
        @echo off\r
        echo Loading quotas...\u{1B}[2J\u{1B}[HCurrent session \u{1B}[5C1%% used\r

        """)
        #else
        try script(named: "contract-cli.sh", """
        #!/bin/sh
        printf 'Loading quotas...\\033[2J\\033[HCurrent session \\033[5C1%% used\\n'

        """)
        #endif
    }

    /// A CLI that asks for a command, then says what it read.
    private func asking() throws -> String {
        #if os(Windows)
        try script(named: "asking-cli.cmd", """
        @echo off\r
        set /p WHAT=Type a command: \r
        echo You typed: %WHAT%\r

        """)
        #else
        try script(named: "asking-cli.sh", """
        #!/bin/sh
        printf 'Type a command: '
        read what
        printf 'You typed: %s\\n' "$what"

        """)
        #endif
    }

    /// A CLI that says the terminal variables it started with.
    private func sayingTerminal() throws -> String {
        #if os(Windows)
        try script(named: "terminal-cli.cmd", """
        @echo off\r
        echo TERM=%TERM% COLORTERM=%COLORTERM% PROBE=%CLAUDEBAR_PROBE%\r

        """)
        #else
        try script(named: "terminal-cli.sh", """
        #!/bin/sh
        printf 'TERM=%s COLORTERM=%s PROBE=%s\\n' "$TERM" "$COLORTERM" "$CLAUDEBAR_PROBE"

        """)
        #endif
    }

    private func script(named name: String, _ text: String) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        try ExecutableFile.write(text, to: file)
        return file.path
    }

    private func executor(_ environment: ProcessEnvironment = ProcessEnvironment()) throws -> any CLIExecutor {
        let make = try #require(Platform.current.runCLI, "\(Platform.current.name) has no terminal")
        return make(CLICall(cli: "contract-cli", environment: environment))
    }

    private func render() throws -> (String) -> String {
        try #require(Platform.current.screenRenderer, "\(Platform.current.name) has no screen renderer")
    }

    @Test
    func `should draw the screen a person would see, cursor moves and all`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await executor().execute(
            binary: try drawing(), args: [], input: "", timeout: 20,
            workingDirectory: nil, autoResponses: [:]
        )
        let screen = try render()(result.output)

        #expect(!screen.contains("\u{1B}"), "the screen a person sees carries no escape codes")
        #expect(screen.contains("Current session      1% used"), "the cursor move lands the text where a terminal puts it")
        #expect(!screen.contains("Loading"), "what the CLI cleared is gone")
    }

    @Test
    func `should give a CLI what is typed into it`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await executor().execute(
            binary: try asking(), args: [], input: "/usage", timeout: 20,
            workingDirectory: nil, autoResponses: [:]
        )

        #expect(try render()(result.output).contains("You typed: /usage"))
    }

    @Test
    func `should start a CLI as a terminal would, with the call's additions winning`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // The app's own TERM is removed, so the terminal's default shows,
        // whatever the machine running the tests has set.
        let change = ProcessEnvironment(unset: ["TERM"], set: ["COLORTERM": "24bit", "CLAUDEBAR_PROBE": "1"])
        let result = try await executor(change).execute(
            binary: try sayingTerminal(), args: [], input: "", timeout: 20,
            workingDirectory: nil, autoResponses: [:]
        )

        #expect(try render()(result.output).contains("TERM=xterm-256color COLORTERM=24bit PROBE=1"))
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
