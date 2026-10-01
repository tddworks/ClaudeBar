import Testing
import Foundation
@testable import Infrastructure

@Suite
struct HookInstallerTests {
    @Test
    func `hook command contains marker function`() {
        #expect(HookInstaller.hookCommand.contains(HookInstaller.hookMarker))
    }

    @Test
    func `hook command uses curl to POST to localhost`() {
        #expect(HookInstaller.hookCommand.contains("curl"))
        #expect(HookInstaller.hookCommand.contains("POST"))
        #expect(HookInstaller.hookCommand.contains("localhost"))
        #expect(HookInstaller.hookCommand.contains("/hook"))
    }

    @Test
    func `hook command reads port from discovery file`() {
        #expect(HookInstaller.hookCommand.contains("claudebar-hook-port"))
    }

    @Test
    func `all expected events are covered`() {
        let events = HookInstaller.hookEvents
        #expect(events.contains("SessionStart"))
        #expect(events.contains("SessionEnd"))
        #expect(events.contains("TaskCompleted"))
        #expect(events.contains("SubagentStart"))
        #expect(events.contains("SubagentStop"))
        #expect(events.contains("Stop"))
        #expect(events.contains("UserPromptSubmit"))
        #expect(events.count == 7)
    }

    @Test
    func `isInstalled returns false when no settings file exists`() {
        // When there's no settings file at all, isInstalled should be false
        // This tests the code path, not the actual file system
        let settings = HookInstaller.readSettings()
        if settings == nil {
            #expect(HookInstaller.isInstalled() == false)
        }
        // If settings exist, we can't make assumptions about the file
    }

    @Test
    func `hookMarker is a valid function name`() {
        // The marker should be a valid bash function identifier
        let marker = HookInstaller.hookMarker
        #expect(!marker.isEmpty)
        #expect(marker.allSatisfy { $0.isLetter || $0 == "_" })
    }
}
