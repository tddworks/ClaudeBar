#if os(Windows)
import Foundation
import Testing
@testable import DataSources

/// Windows starts a program with one variable per name, however a change
/// spells it: its variable names ignore case.
@Suite
struct WindowsEnvironmentTests {
    @Test
    func `should give a default one spelling when the change names it twice`() {
        let environment = WindowsProcesses.environment(
            ProcessEnvironment(defaults: ["TERM": "xterm-256color", "term": "dumb"]),
            base: ["Path": #"C:\Windows"#]
        )

        #expect(environment.keys.filter { $0.uppercased() == "TERM" }.count == 1)
        #expect(environment["Path"] == #"C:\Windows"#)
    }

    @Test
    func `should leave a default unset where the app has the name in another spelling`() {
        let environment = WindowsProcesses.environment(
            ProcessEnvironment(defaults: ["PATH": "default"]),
            base: ["Path": #"C:\Windows"#]
        )

        #expect(environment == ["Path": #"C:\Windows"#])
    }
}
#endif
