import Testing
@testable import DataSources

/// Where a child finds the tools it calls, and where a CLI is looked for, when
/// the app started outside a login shell (#604): the app's own `PATH` first,
/// then the folders tools are installed in, each once.
@Suite
struct ToolFoldersTests {
    @Test
    func `should keep the PATH's folders first, then add each tool folder it lacks, once`() {
        let folders = ToolFolders.folders(
            "/usr/bin:/opt/tools:/bin",
            adding: ["/home/me/.local/bin", "/usr/bin", "/home/me/.local/bin", "/snap/bin"],
            separator: ":"
        )

        #expect(folders == ["/usr/bin", "/opt/tools", "/bin", "/home/me/.local/bin", "/snap/bin"])
    }

    @Test
    func `should skip the PATH's empty entries and keep a folder it already lists twice where it is`() {
        let folders = ToolFolders.folders("/bin::/usr/bin:/bin:", adding: ["/usr/bin"], separator: ":")

        #expect(folders == ["/bin", "/usr/bin", "/bin"])
    }

    @Test
    func `should give a child the app's variables with the merged PATH, then the call's changes`() {
        let environment = ChildEnvironment.exactNames(
            ["PATH": "/usr/bin", "HOME": "/home/me", "TERM": "dumb"],
            program: "/home/me/tools/cli",
            defaultPath: "/bin",
            toolFolders: ["/usr/bin", "/home/me/.local/bin"],
            change: ProcessEnvironment(unset: ["TERM"], defaults: ["HOME": "/x", "LANG": "C.UTF-8"], set: ["X": "1"])
        )

        #expect(environment == [
            "PATH": "/usr/bin:/home/me/tools:/home/me/.local/bin",
            "HOME": "/home/me",
            "LANG": "C.UTF-8",
            "X": "1",
        ])
    }

    @Test
    func `should start from the OS' default PATH when the app has none`() {
        let environment = ChildEnvironment.exactNames(
            [:], program: "/opt/cli", defaultPath: "/usr/bin:/bin", toolFolders: ["/bin", "/snap/bin"],
            change: ProcessEnvironment()
        )

        #expect(environment["PATH"] == "/usr/bin:/bin:/opt:/snap/bin")
    }
}
