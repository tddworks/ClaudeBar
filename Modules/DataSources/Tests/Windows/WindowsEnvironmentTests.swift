#if os(Windows)
import Foundation
import Testing
@testable import DataSources

/// A program's environment on Windows, whose variable names ignore case: a
/// change finds a name however the environment spells it.
@Suite
struct WindowsEnvironmentTests {
    private let base = ["Path": "C:\\Windows", "UserProfile": "C:\\Users\\me", "Gone": "x"]

    @Test
    func `should give a default only where no name of any case has a value`() {
        let change = ProcessEnvironment(defaults: ["PATH": "C:\\other", "USERPROFILE": "C:\\other", "TERM": "xterm-256color"])

        let environment = WindowsProcesses.environment(change, base: base)

        #expect(environment["Path"] == "C:\\Windows")
        #expect(environment["PATH"] == nil)
        #expect(environment["UserProfile"] == "C:\\Users\\me")
        #expect(environment["TERM"] == "xterm-256color")
    }

    @Test
    func `should replace and remove a name however it is spelled`() {
        let change = ProcessEnvironment(unset: ["GONE"], defaults: ["path": "C:\\default"], set: ["PATH": "C:\\tools"])

        let environment = WindowsProcesses.environment(change, base: base)

        #expect(environment["PATH"] == "C:\\tools")
        #expect(environment["Path"] == nil)
        #expect(environment["path"] == nil)
        #expect(environment["Gone"] == nil)
    }
}
#endif
