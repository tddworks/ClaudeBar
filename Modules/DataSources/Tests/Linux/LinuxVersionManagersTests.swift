#if os(Linux)
import Foundation
import Testing
@testable import DataSources

/// A CLI installed with a Node or tool version manager is found without a
/// shell (#682): the managers put their folders on `PATH` only in shell setup,
/// which a service or `wsl.exe -e` never reads.
@Suite
struct LinuxVersionManagersTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// An executable file at `name` under `root`, and its path.
    @discardableResult
    private func executable(_ name: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// A text file at `name` under `root`, as nvm writes an alias.
    private func file(_ name: String, _ text: String) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A locator with a service's `PATH` and the tool folders of a home at `root`.
    private func locator(environment: [String: String] = [:]) -> LinuxBinaryLocator {
        LinuxBinaryLocator(environment: { ["PATH": "/usr/bin:/bin"] },
                           toolFolders: LinuxProcesses.commonPaths(home: root.path, environment: environment))
    }

    @Test(arguments: [
        ".nvm/versions/node/v22.0.0/bin/codex",
        ".volta/bin/claude",
        ".local/share/fnm/aliases/default/bin/gemini",
        ".local/share/mise/shims/opencode",
        ".asdf/shims/kimi",
    ])
    func `should find a CLI where a version manager installs it, with no shell`(_ installed: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try executable(installed)

        #expect(locator().locate(URL(fileURLWithPath: installed).lastPathComponent) == tool)
    }

    @Test(arguments: [
        ("data/fnm/aliases/default/bin/gemini", ".local/share/fnm/aliases/default/bin/gemini"),
        ("data/mise/shims/opencode", ".local/share/mise/shims/opencode"),
        // nvm's installer uses `$XDG_CONFIG_HOME/nvm` when that is set.
        ("config/nvm/versions/node/v22.0.0/bin/codex", ".nvm/versions/node/v22.0.0/bin/codex"),
    ])
    func `should find a CLI under the XDG folders the person moved, before the default ones`(
        moved: String, usual: String
    ) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try executable(moved)
        try executable(usual)

        let locator = locator(environment: ["XDG_DATA_HOME": root.appendingPathComponent("data").path,
                                            "XDG_CONFIG_HOME": root.appendingPathComponent("config").path])
        #expect(locator.locate(URL(fileURLWithPath: moved).lastPathComponent) == tool)
    }

    /// nvm's installed versions, in no order, each with its own Codex.
    private func nvmVersions() throws {
        for version in ["v20.9.0", "v9.11.2", "v22.0.0", "v18.20.0", "v20.11.1"] {
            try executable(".nvm/versions/node/\(version)/bin/codex")
        }
    }

    /// The nvm versions whose `bin` the tool folders list, in their order.
    private func nvmOrder() -> [String] {
        LinuxProcesses.commonPaths(home: root.path, environment: [:])
            .filter { $0.hasPrefix(root.appendingPathComponent(".nvm/versions/node").path) }
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }
    }

    @Test
    func `should list nvm's versions newest first, by number, when there is no default alias`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try nvmVersions()

        #expect(nvmOrder() == ["v22.0.0", "v20.11.1", "v20.9.0", "v18.20.0", "v9.11.2"])
        #expect(locator().locate("codex") == root.appendingPathComponent(".nvm/versions/node/v22.0.0/bin/codex").path)
    }

    @Test(arguments: [
        // A major version: its newest installed one.
        ("20", "v20.11.1"),
        // A full version, with or without the `v`.
        ("v18.20.0", "v18.20.0"),
        ("9.11.2", "v9.11.2"),
        // A major and minor.
        ("20.9", "v20.9.0"),
        // `node` and `stable` are the newest.
        ("node", "v22.0.0"),
        ("stable", "v22.0.0"),
        // `2` is not `22`: nothing matches, so newest first.
        ("2", "v22.0.0"),
        // `system` names no nvm version: newest first.
        ("system", "v22.0.0"),
    ])
    func `should put nvm's default alias first`(alias: String, first: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try nvmVersions()
        try file(".nvm/alias/default", alias + "\n")

        let order = nvmOrder()
        #expect(order.first == first)
        #expect(Array(order.dropFirst()) == ["v22.0.0", "v20.11.1", "v20.9.0", "v18.20.0", "v9.11.2"].filter { $0 != first })
    }

    @Test
    func `should follow nvm's lts aliases to the version they name`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try nvmVersions()
        try file(".nvm/alias/default", "lts/*\n")
        try file(".nvm/alias/lts/*", "lts/iron\n")
        try file(".nvm/alias/lts/iron", "v20.9.0\n")

        #expect(nvmOrder().first == "v20.9.0")
        #expect(locator().locate("codex") == root.appendingPathComponent(".nvm/versions/node/v20.9.0/bin/codex").path)
    }

    @Test
    func `should list nvm's versions newest first when the lts alias has no file`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try nvmVersions()
        try file(".nvm/alias/default", "lts/*\n")

        #expect(nvmOrder() == ["v22.0.0", "v20.11.1", "v20.9.0", "v18.20.0", "v9.11.2"])
    }

    @Test
    func `should give a child the version managers' folders on its PATH, so a Node script finds its node`() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try executable(".nvm/versions/node/v22.0.0/bin/node")
        let data = root.appendingPathComponent("data").path
        let home = root.path

        let programs = LinuxProcesses(appEnvironment: { ["PATH": "/usr/bin:/bin", "XDG_DATA_HOME": data] },
                                      home: { home })
        let path = programs.environment(for: "/opt/tools/codex", ProcessEnvironment())["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init)

        #expect(Array(folders.prefix(3)) == ["/usr/bin", "/bin", "/opt/tools"])
        for folder in ["\(home)/.nvm/versions/node/v22.0.0/bin", "\(home)/.volta/bin",
                       "\(data)/fnm/aliases/default/bin", "\(home)/.local/share/fnm/aliases/default/bin",
                       "\(data)/mise/shims", "\(home)/.local/share/mise/shims", "\(home)/.asdf/shims"] {
            #expect(folders.contains(folder), "\(folder) on the child's PATH")
        }
    }

    @Test(arguments: [
        ".nvm/versions/node/v22.0.0/bin/codex",
        "data/fnm/aliases/default/bin/gemini",
        ".asdf/shims/kimi",
    ])
    func `should put a version manager's folder first on its CLI's PATH, so env node finds the manager's Node`(
        _ installed: String
    ) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = try executable(installed)
        let data = root.appendingPathComponent("data").path
        let home = root.path

        // A distro's own, older `node` in /usr/bin would win after the app's PATH.
        let programs = LinuxProcesses(appEnvironment: { ["PATH": "/usr/bin:/bin", "XDG_DATA_HOME": data] },
                                      home: { home })
        let path = programs.environment(for: tool, ProcessEnvironment())["PATH"] ?? ""
        let folders = path.split(separator: ":").map(String.init)

        let folder = URL(fileURLWithPath: tool).deletingLastPathComponent().path
        #expect(Array(folders.prefix(3)) == [folder, "/usr/bin", "/bin"])
        #expect(folders.filter { $0 == folder }.count == 1)
    }
}
#endif
