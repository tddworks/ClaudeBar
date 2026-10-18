import Foundation
import Quotas
import Testing
@testable import DataSources

/// The `Processes` port's contract (MODULAR_DESIGN §10), run against this
/// platform's adapter. Its programs are scripts the suite writes in this
/// platform's own script language, in a folder whose name has a space,
/// brackets and an ampersand: the characters a path most often breaks on.
@Suite
struct ProcessesContract {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("processes (x86) & \(UUID().uuidString.prefix(8))", isDirectory: true)

    private func processes() throws -> any Processes {
        try #require(Platform.current.processes, "\(Platform.current.name) has no Processes adapter")
    }

    /// A script holding `text`, written in the suite's folder.
    private func script(_ name: String, _ text: String) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(name).\(Programs.scriptExtension)")
        try Data(text.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file.path
    }

    @Test func `should find a program on the PATH by name, a script by its path, and nothing for a name that isn't there`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let processes = try processes()
        let shell = try #require(processes.locate(Programs.shell))
        #expect(FileManager.default.isExecutableFile(atPath: shell))
        let path = try script("answer", Programs.answer)
        #expect(processes.locate(path).map(Programs.same) == Programs.same(path))
        #expect(processes.locate("claudebar-no-such-cli") == nil)
    }

    @Test func `should run a script from its folder with its variables and input, answering what it printed and its exit code`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let processes = try processes()
        let argv = processes.script(try script("answer", Programs.answer))
        let runner = processes.runner(ProcessEnvironment(set: ["CONTRACT_VAR": "x y"]))

        let result = try await runner.execute(binary: argv[0], args: Array(argv.dropFirst()), input: "hello\n",
                                              timeout: 30, workingDirectory: folder, autoResponses: [:])

        #expect(result.exitCode == 3)
        #expect(result.output.contains("var=x y line=hello"))
        #expect(result.output.contains("oops"), "what it printed on stderr is part of the answer")
        let printed = result.output.split(whereSeparator: \.isNewline).first { $0.hasPrefix("folder=") }
        #expect(printed.map { Programs.same(String($0.dropFirst("folder=".count))) } == Programs.same(folder.path))
    }

    @Test func `should report a program it can't find`() async throws {
        let runner = try processes().runner(ProcessEnvironment())
        await #expect(throws: UsageError.cliNotFound("claudebar-no-such-cli")) {
            try await runner.execute(binary: "claudebar-no-such-cli", args: [], input: nil, timeout: 5,
                                     workingDirectory: nil, autoResponses: [:])
        }
    }

    @Test func `should stop a program that runs past its timeout`() async throws {
        let runner = try processes().runner(ProcessEnvironment())
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: UsageError.timeout) {
            try await runner.execute(binary: Programs.wait.binary, args: Programs.wait.args, input: nil, timeout: 1,
                                     workingDirectory: nil, autoResponses: [:])
        }
        #expect(clock.now - start < .seconds(10))
    }

    @Test func `should hold a line-by-line conversation with a program, and end it`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let processes = try processes()
        let argv = processes.script(try script("echo", Programs.echo))
        let transport = try processes.converse(argv[0], Array(argv.dropFirst()), nil, folder)

        for message in [#"{"id":1}"#, #"{"id":2}"#] {
            try transport.send(Data(message.utf8))
            #expect(String(decoding: try await transport.receive(), as: UTF8.self) == message)
        }
        transport.close()
        await #expect(throws: (any Error).self) { try await transport.receive() }
    }

    @Test func `should list the program this test runs in among those running`() throws {
        let own = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().lastPathComponent
        let names = try processes().running().map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
        #expect(names.contains(own.lowercased()))
    }

    @Test func `should read a variable as the person's login sets it`() async throws {
        let processes = try processes()
        let login = LoginShellEnvironment(cliExecutor: processes.runner(ProcessEnvironment(set: ["CLAUDEBAR_CONTRACT": "a b"])),
                                          command: { processes.loginVariable($0) }, timeout: 30)
        #expect(await login.value(ofEnvVar: "CLAUDEBAR_CONTRACT") == "a b")
    }
}

/// The programs the contract runs, in this platform's own terms.
private enum Programs {
    #if os(Windows)
    static let scriptExtension = "cmd"
    static let shell = "cmd"
    // Delayed expansion (`!CD!`) reads a value after the line is parsed, so
    // the folder's `&` is printed rather than run as a second command.
    static let answer = """
        @echo off\r
        setlocal EnableDelayedExpansion\r
        set /p LINE=\r
        echo var=!CONTRACT_VAR! line=!LINE!\r
        echo folder=!CD!\r
        echo oops 1>&2\r
        exit /b 3\r

        """
    static let echo = """
        @echo off\r
        :next\r
        set LINE=\r
        set /p LINE=\r
        if not defined LINE exit /b 0\r
        echo %LINE%\r
        goto next\r

        """
    static let wait = (binary: "ping", args: ["-n", "30", "127.0.0.1"])
    #else
    static let scriptExtension = "sh"
    static let shell = "sh"
    static let answer = """
        #!/bin/sh
        IFS= read -r LINE
        echo "var=$CONTRACT_VAR line=$LINE"
        echo "folder=$(pwd)"
        echo oops >&2
        exit 3

        """
    static let echo = """
        #!/bin/sh
        while IFS= read -r LINE; do echo "$LINE"; done

        """
    static let wait = (binary: "sleep", args: ["30"])
    #endif

    /// A path as the file system compares it: links followed, and on
    /// Windows either slash and any case.
    static func same(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        #if os(Windows)
        return resolved.replacingOccurrences(of: "\\", with: "/").lowercased()
        #else
        return resolved
        #endif
    }
}
