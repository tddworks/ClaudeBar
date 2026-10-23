import Foundation
import Quotas
import Testing
@testable import DataSources
#if os(Windows)
import WinSDK
#endif

/// The `Processes` port's contract (MODULAR_DESIGN §10), run against this
/// platform's adapter. Its programs are scripts the suite writes in this
/// platform's own script language, in a folder whose name has a space,
/// brackets and an ampersand: the characters a path most often breaks on.
@Suite
struct ProcessesContract {
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("processes (x86) & \(UUID().uuidString.prefix(8))", isDirectory: true)

    private func processes() throws -> Processes {
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
        let installed = try processes().installed
        let shell = try #require(installed.find(Programs.shell))
        #expect(FileManager.default.isExecutableFile(atPath: shell))
        let path = try script("answer", Programs.answer)
        #expect(installed.find(path).map(Programs.same) == Programs.same(path))
        #expect(installed.find("claudebar-no-such-cli") == nil)
    }

    @Test func `should run a script from its folder with its variables and input, answering what it printed`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = try #require(try processes().script(at: try script("answer", Programs.answer)))

        let output = try await script.run(input: "hello\n", environment: ProcessEnvironment(set: ["CONTRACT_VAR": "x y"]),
                                          timeout: 30, in: folder)

        #expect(output.contains("var=x y line=hello"))
        #expect(output.contains("oops"), "what it printed on stderr is part of the answer")
        let printed = output.split(whereSeparator: \.isNewline).first { $0.hasPrefix("folder=") }
        #expect(printed.map { Programs.same(String($0.dropFirst("folder=".count))) } == Programs.same(folder.path))
    }

    @Test func `should report the code a script exited with`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = try #require(try processes().script(at: try script("fail", Programs.fail)))
        await #expect {
            try await script.run(timeout: 30, in: folder)
        } throws: { ($0 as? CLIExitError)?.exitCode == 3 }
    }

    @Test func `should find no program or script that isn't there`() throws {
        let processes = try processes()
        #expect(processes.program(named: "claudebar-no-such-cli") == nil)
        #expect(processes.script(at: folder.appendingPathComponent("missing").path) == nil)
    }

    @Test func `should stop a program that runs past its timeout`() async throws {
        let program = try #require(try processes().program(named: Programs.wait.binary))
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: UsageError.timeout) {
            try await program.run(Programs.wait.args, timeout: 1, in: nil)
        }
        // The program runs ten minutes; the run must end long before that,
        // not wait for it. The margin is wide because a CI runner can stall
        // every test for half a minute at once.
        #expect(clock.now - start < .seconds(120))
    }

    @Test func `should hold a line-by-line conversation with a program, and end it`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = try #require(try processes().script(at: try script("echo", Programs.echo)))
        let transport = try script.talk([], in: folder)

        for message in [#"{"id":1}"#, #"{"id":2}"#] {
            try transport.send(Data(message.utf8))
            #expect(String(decoding: try await transport.receive(), as: UTF8.self) == message)
        }
        transport.close()
        await #expect(throws: (any Error).self) { try await transport.receive() }
    }

    /// A file the app is writing stays the app's: a program it starts talking
    /// to meanwhile mustn't get a copy of the file's handle. Windows hands a
    /// child every handle the app may pass on unless the launch names the ones
    /// it gets, and a copy left in the program kept an atomic write from
    /// moving its temporary file into place (Win32 error 32) for as long as
    /// the program ran.
    @Test func `should not hand a program it talks to a file the app has open`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = try #require(try processes().script(at: try script("echo", Programs.echo)))
        let file = folder.appendingPathComponent("being written.tmp")
        let close = try Programs.openAsAnAtomicWriteDoes(file)
        let transport = try script.talk([], in: folder)
        defer { transport.close() }
        // An answer means the program started while the file was open.
        try transport.send(Data("ready".utf8))
        #expect(String(decoding: try await transport.receive(), as: UTF8.self) == "ready")

        close()

        #expect(throws: Never.self) { try FileManager.default.removeItem(at: file) }
    }

    @Test func `should read a variable as the person's login sets it`() async throws {
        let processes = try processes()
        let login = processes.loginEnvironment(runner: processes.pipes(ProcessEnvironment(set: ["CLAUDEBAR_CONTRACT": "a b"])),
                                               timeout: 30)
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
        exit /b 0\r

        """
    static let fail = """
        @echo off\r
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
    static let wait = (binary: "ping", args: ["-n", "600", "127.0.0.1"])
    #else
    static let scriptExtension = "sh"
    static let shell = "sh"
    static let answer = """
        #!/bin/sh
        IFS= read -r LINE
        echo "var=$CONTRACT_VAR line=$LINE"
        echo "folder=$(pwd)"
        echo oops >&2

        """
    static let fail = """
        #!/bin/sh
        exit 3

        """
    static let echo = """
        #!/bin/sh
        while IFS= read -r LINE; do echo "$LINE"; done

        """
    static let wait = (binary: "sleep", args: ["600"])
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

    /// Opens `file` as Foundation's atomic write opens its temporary file: a
    /// C runtime descriptor a child started meanwhile may inherit, which on
    /// Windows doesn't share deleting. Answers how to close it.
    static func openAsAnAtomicWriteDoes(_ file: URL) throws -> () -> Void {
        #if os(Windows)
        var descriptor: Int32 = -1
        _ = file.path.withCString(encodedAs: UTF16.self) {
            _wsopen_s(&descriptor, $0, _O_RDWR | _O_CREAT, _SH_DENYNO, _S_IREAD | _S_IWRITE)
        }
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        return { _ = _close(descriptor) }
        #else
        let descriptor = open(file.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        return { _ = close(descriptor) }
        #endif
    }
}
