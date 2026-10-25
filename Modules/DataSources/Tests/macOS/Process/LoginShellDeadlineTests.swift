#if os(macOS)
import Testing
import Foundation
@testable import DataSources

/// The login shell that finds a CLI and its `PATH` answers within a deadline
/// (#550): a refresh starts a CLI only after asking it, so a shell that never
/// finishes used to hold the refresh, and every later one, before any fetch's
/// own deadline began.
@Suite(.timeLimit(.minutes(1)))
struct LoginShellDeadlineTests {
    /// A stand-in for the person's shell: a script named `zsh`, so it gets
    /// zsh's arguments, that does what `body` says whatever it's asked.
    private struct FakeShell {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cb-shell-\(UUID().uuidString)", isDirectory: true)
        var path: String { folder.appendingPathComponent("zsh").path }
        var leftChild: String { folder.appendingPathComponent("child.pid").path }

        init(_ body: String) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ExecutableFile.write("#!/bin/sh\n\(body)\n", to: URL(fileURLWithPath: path))
        }

        func remove() {
            if let pid = (try? String(contentsOfFile: leftChild, encoding: .utf8)).flatMap({ pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test
    func `should give up on a login shell that never finishes, and use the app's own PATH`() throws {
        let shell = try FakeShell("exec sleep 20")
        defer { shell.remove() }

        let started = Date()
        let path = BinaryLocator.computeShellPath(preferredShell: shell.path, timeout: 0.5)

        #expect(Date().timeIntervalSince(started) < 5)
        #expect(path == (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"))
    }

    @Test
    func `should take a login shell's answer when it exits, even while a program it started keeps its output open`() throws {
        // As `.zprofile` starting an agent does: the shell answers and exits,
        // but its output reaches end-of-file only when the agent exits.
        let shell = try FakeShell("sleep 20 &\necho $! > \"$(dirname \"$0\")/child.pid\"\necho /opt/fake/bin/tool")
        defer { shell.remove() }

        let started = Date()
        let path = BinaryLocator.whichViaShell("tool", preferredShell: shell.path, timeout: 10)

        #expect(Date().timeIntervalSince(started) < 5)
        #expect(path == "/opt/fake/bin/tool")
    }
}
#endif
