import Testing
import Foundation
import Domain
@testable import Infrastructure

@Suite
struct HookInstallerTests {
    @Test
    func `should carry ClaudeBar's marker so the installed hook can be recognised as ClaudeBar's`() {
        #expect(HookInstaller.hookCommand.contains(HookInstaller.hookMarker))
    }

    @Test
    func `should send each Claude Code event to ClaudeBar on this Mac`() {
        #expect(HookInstaller.hookCommand.contains("curl"))
        #expect(HookInstaller.hookCommand.contains("POST"))
        #expect(HookInstaller.hookCommand.contains("localhost"))
        #expect(HookInstaller.hookCommand.contains("/hook"))
    }

    @Test
    func `should tell ClaudeBar which Claude Code process sent the event, so it can notice when it is gone`() {
        #expect(HookInstaller.hookCommand.contains("-H \"\(HookConstants.processIdHeader): $CLAUDE_PID\""))
    }

    @Test
    func `should find ClaudeBar's port in the file ClaudeBar leaves for it`() {
        #expect(HookInstaller.hookCommand.contains("claudebar-hook-port"))
    }

    @Test
    func `should listen to the eight session events Claude Code reports`() {
        let events = HookInstaller.hookEvents
        #expect(events.contains("StopFailure"))
        #expect(events.contains("SessionStart"))
        #expect(events.contains("SessionEnd"))
        #expect(events.contains("TaskCompleted"))
        #expect(events.contains("SubagentStart"))
        #expect(events.contains("SubagentStop"))
        #expect(events.contains("Stop"))
        #expect(events.contains("UserPromptSubmit"))
        #expect(events.count == 8)
    }

    // MARK: - Claude Code's settings file

    /// A settings file in its own temporary folder, never the person's own.
    private struct SettingsFile {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hook-installer-\(UUID().uuidString)")
        var path: String { folder.appendingPathComponent(".claude/settings.json").path }

        func write(_ json: String) throws {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        }

        func read() throws -> [String: Any] {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func hooks(_ event: String) throws -> [[String: Any]] {
            (try read()["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }
    }

    private func commands(_ entries: [[String: Any]]) -> [String] {
        entries.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    @Test
    func `should count the hook not installed when Claude Code has no settings file`() {
        let file = SettingsFile()
        #expect(HookInstaller.isInstalled(at: file.path) == false)
    }

    @Test
    func `should create Claude Code's settings with the hook on every session event when there is none yet`() throws {
        let file = SettingsFile()
        defer { file.remove() }

        try HookInstaller.install(at: file.path)

        #expect(HookInstaller.isInstalled(at: file.path))
        for event in HookInstaller.hookEvents {
            #expect(try commands(file.hooks(event)) == [HookInstaller.hookCommand])
        }
    }

    @Test
    func `should keep the person's own settings and other tools' hooks when turning the hook on`() throws {
        let file = SettingsFile()
        defer { file.remove() }
        try file.write(#"{"model":"opus","hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"say done"}]}]}}"#)

        try HookInstaller.install(at: file.path)

        #expect(try file.read()["model"] as? String == "opus")
        #expect(try commands(file.hooks("Stop")) == ["say done", HookInstaller.hookCommand])
    }

    @Test
    func `should add the hook once when it is turned on twice`() throws {
        let file = SettingsFile()
        defer { file.remove() }

        try HookInstaller.install(at: file.path)
        try HookInstaller.install(at: file.path)

        #expect(try commands(file.hooks("SessionStart")) == [HookInstaller.hookCommand])
    }

    @Test
    func `should remove only ClaudeBar's hook when turning it off, leaving other tools' hooks`() throws {
        let file = SettingsFile()
        defer { file.remove() }
        try file.write(#"{"hooks":{"Stop":[{"matcher":".*","hooks":[{"type":"command","command":"say done"}]}]}}"#)
        try HookInstaller.install(at: file.path)

        try HookInstaller.uninstall(at: file.path)

        #expect(HookInstaller.isInstalled(at: file.path) == false)
        #expect(try commands(file.hooks("Stop")) == ["say done"])
        #expect((try file.read()["hooks"] as? [String: Any])?["SessionStart"] == nil)
    }

    @Test
    func `should leave no empty hooks section once the hook is turned off`() throws {
        let file = SettingsFile()
        defer { file.remove() }
        try file.write(#"{"model":"opus"}"#)
        try HookInstaller.install(at: file.path)

        try HookInstaller.uninstall(at: file.path)

        #expect(try file.read()["hooks"] == nil)
        #expect(try file.read()["model"] as? String == "opus")
    }

    @Test
    func `should refuse to change a settings file it cannot read, and leave it as it was`() throws {
        let file = SettingsFile()
        defer { file.remove() }
        try file.write("{ not json")

        #expect(throws: (any Error).self) { try HookInstaller.install(at: file.path) }
        #expect(try String(contentsOfFile: file.path, encoding: .utf8) == "{ not json")
        #expect(HookInstaller.isInstalled(at: file.path) == false)
    }

    @Test
    func `should treat an empty settings file as no settings`() throws {
        let file = SettingsFile()
        defer { file.remove() }
        try file.write("")

        try HookInstaller.install(at: file.path)

        #expect(HookInstaller.isInstalled(at: file.path))
    }

    @Test
    func `should mark the hook with a name the shell accepts as a function name`() {
        // The marker should be a valid bash function identifier
        let marker = HookInstaller.hookMarker
        #expect(!marker.isEmpty)
        #expect(marker.allSatisfy { $0.isLetter || $0 == "_" })
    }

    // MARK: - Probe sessions (issue #222)

    @Test
    func `should send nothing when the session is ClaudeBar's own Claude run (#222)`() {
        let command = HookInstaller.hookCommand

        // The guard references the probe marker and returns before any POST.
        let probeGuard = command.range(
            of: "[ \"$\(HookConstants.probeEnvironmentKey)\" = \"1\" ] && return 0"
        )
        #expect(probeGuard != nil)

        if let probeGuard, let curl = command.range(of: "curl") {
            #expect(probeGuard.lowerBound < curl.lowerBound)
        }
    }
}
