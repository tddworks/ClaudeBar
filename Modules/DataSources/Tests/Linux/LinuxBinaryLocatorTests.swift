#if os(Linux)
import Foundation
import Testing
@testable import DataSources

/// Linux finds a CLI as the shell's `PATH` does, and takes a path to one as it
/// is.
@Suite
struct LinuxBinaryLocatorTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// An executable file at `name` under `root`, and its path.
    private func executable(_ name: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func locator(path: [String], toolFolders: [String] = []) -> LinuxBinaryLocator {
        LinuxBinaryLocator(environment: { ["PATH": path.joined(separator: ":")] }, toolFolders: toolFolders)
    }

    @Test
    func `should find a name in the first PATH folder that has it`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try executable("bin/claude")
        _ = try executable("later/claude")

        let path = [root.appendingPathComponent("empty").path, root.appendingPathComponent("bin").path,
                    root.appendingPathComponent("later").path]
        #expect(locator(path: path).locate("claude") == tool)
    }

    @Test
    func `should take a full path to the CLI as it is, without searching PATH`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try executable("tools/claude")
        _ = try executable("bin/claude")

        #expect(locator(path: [root.appendingPathComponent("bin").path]).locate(tool) == tool)
    }

    @Test
    func `should find a CLI in a tool folder the PATH lacks, as when the app runs as a service (#604)`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try executable("home/.local/bin/claude")

        let locator = locator(path: [root.appendingPathComponent("usr/bin").path],
                              toolFolders: [root.appendingPathComponent("home/.local/bin").path])
        #expect(locator.locate("claude") == tool)
    }

    @Test
    func `should prefer the PATH's copy of a CLI to a tool folder's`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let onPath = try executable("bin/claude")
        _ = try executable("home/.local/bin/claude")

        let locator = locator(path: [root.appendingPathComponent("bin").path],
                              toolFolders: [root.appendingPathComponent("home/.local/bin").path])
        #expect(locator.locate("claude") == onPath)
    }

    @Test
    func `should find nothing for a name that isn't there, and nothing for a file that isn't executable`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let plain = root.appendingPathComponent("plain")
        try Data().write(to: plain)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain.path)

        let locator = locator(path: [root.path])
        #expect(locator.locate("claudebar-no-such-cli") == nil)
        #expect(locator.locate("plain") == nil)
        #expect(locator.locate(plain.path) == nil)
    }
}
#endif
