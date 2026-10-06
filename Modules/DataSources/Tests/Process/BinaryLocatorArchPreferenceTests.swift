import Foundation
import Testing

@testable import DataSources

/// Which binary ClaudeBar picks and spawns (issue #251): an Intel-only CLI or
/// login shell runs under Rosetta, and macOS names ClaudeBar — the app that
/// spawned it — in its "apps for Intel processors" warning.
@Suite
struct BinaryLocatorArchPreferenceTests {

    // MARK: - Which shell binary the PATH lookups spawn

    @Test
    func `should keep the user's shell when it runs natively on this Mac`() {
        let path = BinaryLocator.whichShellPath(
            preferred: "/opt/homebrew/bin/fish",
            machine: .arm64,
            preferredSlices: [.arm64]
        )

        #expect(path == "/opt/homebrew/bin/fish")
    }

    @Test
    func `should keep a universal shell as it is`() {
        let path = BinaryLocator.whichShellPath(
            preferred: "/bin/zsh",
            machine: .arm64,
            preferredSlices: [.arm64, .x86_64]
        )

        #expect(path == "/bin/zsh")
    }

    @Test
    func `should keep the user's shell when its architecture can't be read`() {
        // No arch info is no reason to override anything.
        let path = BinaryLocator.whichShellPath(
            preferred: "/usr/local/bin/fish",
            machine: .arm64,
            preferredSlices: nil
        )

        #expect(path == "/usr/local/bin/fish")
    }

    @Test
    func `should spawn the system shell when the user's shell is Intel-only on an arm64 Mac`() {
        let path = BinaryLocator.whichShellPath(
            preferred: "/usr/local/bin/zsh",
            machine: .arm64,
            preferredSlices: [.x86_64]
        )

        #expect(path == "/bin/zsh")
    }

    @Test
    func `should keep an Intel-only shell on an Intel Mac`() {
        let path = BinaryLocator.whichShellPath(
            preferred: "/usr/local/bin/zsh",
            machine: .x86_64,
            preferredSlices: [.x86_64]
        )

        #expect(path == "/usr/local/bin/zsh")
    }

    @Test
    func `should spawn the system shell when the user's shell can't run on this Mac at all`() {
        let path = BinaryLocator.whichShellPath(
            preferred: "/opt/homebrew/bin/zsh",
            machine: .x86_64,
            preferredSlices: [.arm64]
        )

        #expect(path == "/bin/zsh")
    }

    @Test
    func `should wire the guard to the user's own shell`() {
        // The wiring overload reads the real shell binary. On any Mac from the
        // last several years /bin/zsh is universal, so it must stand as is.
        #expect(BinaryLocator.whichShellPath(preferred: "/bin/zsh") == "/bin/zsh")
    }

    // MARK: - Which copy of a tool wins when several folders have one

    @Test
    func `should prefer the native copy when two folders both have the CLI`() throws {
        try withTwoInstalls(.x86_64, second: .arm64) { intelFirst, second in
            let found = BinaryLocator.candidates(in: [intelFirst.base, second.base], tool: "fixture-tool")

            #expect(found.first == second.toolPath)
            #expect(found.count == 2)
        }
    }

    @Test
    func `should keep the folder order when the first copy is already native`() throws {
        try withTwoInstalls(.arm64, second: .x86_64) { first, second in
            let found = BinaryLocator.candidates(in: [first.base, second.base], tool: "fixture-tool")

            #expect(found.first == first.toolPath)
        }
    }

    @Test
    func `should keep the folder order when neither copy is native`() throws {
        try withTwoInstalls(.x86_64, second: .x86_64) { first, second in
            let found = BinaryLocator.candidates(in: [first.base, second.base], tool: "fixture-tool")

            #expect(found.first == first.toolPath)
        }
    }

    @Test
    func `should keep the folder order when neither copy's architecture can be read`() throws {
        // Scripts (the npm-wrapper shape) carry no arch info; nothing may change.
        try withTwoInstalls(nil, second: nil) { first, second in
            let found = BinaryLocator.candidates(in: [first.base, second.base], tool: "fixture-tool")

            #expect(found.first == first.toolPath)
            #expect(found.count == 2)
        }
    }

    @Test
    func `should prefer the older nvm version's native copy over a newer Intel-only one`() throws {
        try withNvmInstalls(v24_10: .arm64, v24_11: .x86_64) { base, older, newer in
            let found = BinaryLocator.candidates(in: [base], tool: "fixture-tool")

            // The versions folder contributes one candidate: its best.
            #expect(found == [older])
        }
    }

    @Test
    func `should keep the newer nvm version when both copies are native`() throws {
        try withNvmInstalls(v24_10: .arm64, v24_11: .arm64) { base, older, newer in
            let found = BinaryLocator.candidates(in: [base], tool: "fixture-tool")

            #expect(found.first == newer)
        }
    }

    @Test
    func `should keep the newer nvm version when neither copy says its architecture`() throws {
        try withNvmInstalls(v24_10: nil, v24_11: nil) { base, older, newer in
            let found = BinaryLocator.candidates(in: [base], tool: "fixture-tool")

            #expect(found.first == newer)
        }
    }

    // MARK: - When the login shell's answer gets overridden

    @Test
    func `should keep the shell's answer when it runs natively`() throws {
        try withInstalls([.arm64]) { paths in
            let settled = BinaryLocator.settled(
                tool: "fixture-tool",
                shellAnswer: paths[0],
                fallbackCandidates: []
            )

            #expect(settled == paths[0])
        }
    }

    @Test
    func `should keep the shell's answer when its architecture can't be read`() throws {
        try withInstalls([nil]) { paths in
            let settled = BinaryLocator.settled(
                tool: "fixture-tool",
                shellAnswer: paths[0],
                fallbackCandidates: []
            )

            #expect(settled == paths[0])
        }
    }

    @Test
    func `should keep the shell's Intel-only answer when no native copy exists in the fallback folders`() throws {
        try withInstalls([.x86_64, .x86_64]) { paths in
            let settled = BinaryLocator.settled(
                tool: "fixture-tool",
                shellAnswer: paths[0],
                fallbackCandidates: [paths[1]]
            )

            #expect(settled == paths[0])
        }
    }

    @Test
    func `should prefer the fallback folders' native copy over the shell's Intel-only answer`() throws {
        try withInstalls([.x86_64, .arm64]) { paths in
            let settled = BinaryLocator.settled(
                tool: "fixture-tool",
                shellAnswer: paths[0],
                fallbackCandidates: [paths[1]]
            )

            #expect(settled == paths[1])
        }
    }

    // MARK: - Fixtures

    private struct Install {
        let base: String
        let toolPath: String
    }

    /// Two install folders, each with `fixture-tool` built for the given
    /// architecture (nil = a shell script with no arch info).
    private func withTwoInstalls(
        _ first: BinaryArchitecture?,
        second: BinaryArchitecture?,
        _ body: (Install, Install) throws -> Void
    ) throws {
        try withRoot { root in
            let first = try install(arch: first, name: "fixture-tool", subpath: "first/bin", root: root)
            let second = try install(arch: second, name: "fixture-tool", subpath: "second/bin", root: root)
            try body(first, second)
        }
    }

    /// An nvm-style versions folder with two node versions, older and newer.
    private func withNvmInstalls(
        v24_10: BinaryArchitecture?,
        v24_11: BinaryArchitecture?,
        _ body: (String, String, String) throws -> Void
    ) throws {
        try withRoot { root in
            let versionsBase = root.appendingPathComponent("nvm/versions").path
            let older = try install(
                arch: v24_10,
                name: "fixture-tool",
                subpath: "nvm/versions/node/v24.10.0/bin",
                root: root
            )
            let newer = try install(
                arch: v24_11,
                name: "fixture-tool",
                subpath: "nvm/versions/node/v24.11.0/bin",
                root: root
            )
            try body(versionsBase, older.toolPath, newer.toolPath)
        }
    }

    private func withInstalls(
        _ archs: [BinaryArchitecture?],
        _ body: ([String]) throws -> Void
    ) throws {
        try withRoot { root in
            var paths: [String] = []
            for (index, arch) in archs.enumerated() {
                paths.append(try install(arch: arch, name: "fixture-tool", subpath: "dir\(index)/bin", root: root).toolPath)
            }
            try body(paths)
        }
    }

    private func install(arch: BinaryArchitecture?, name: String, subpath: String, root: URL) throws -> Install {
        let data: Data
        switch arch {
        case .arm64: data = MachOFixtures.thin(.arm64)
        case .x86_64: data = MachOFixtures.thin(.x86_64)
        case nil: data = MachOFixtures.shellScript
        }
        let toolPath = try MachOFixtures.writeExecutable(data, name: name, in: root, subpath: subpath)
        return Install(
            base: URL(fileURLWithPath: toolPath).deletingLastPathComponent().path,
            toolPath: toolPath
        )
    }

    private func withRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
