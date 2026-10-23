#if !os(Windows)
import Foundation
import Testing
@testable import DataSources

/// A program's environment on POSIX (the Mac's and Linux' `ChildLaunch`): a
/// default fills only a name the environment lacks, a value set wins, and a
/// name is matched exactly, as the OS matches it.
@Suite
struct ChildEnvironmentTests {
    private let programs = PlatformTerminal.programs
    private let home = ProcessInfo.processInfo.environment["HOME"]

    @Test
    func `should give a program a default only where its environment has none`() {
        let change = ProcessEnvironment(defaults: ["HOME": "/elsewhere", "CLAUDEBAR_DEFAULT": "d"])

        let environment = programs.environment(for: "/bin/sh", change)

        #expect(environment["HOME"] == home)
        #expect(environment["CLAUDEBAR_DEFAULT"] == "d")
    }

    @Test
    func `should let a value set win over a default for the same name`() {
        let change = ProcessEnvironment(defaults: ["CLAUDEBAR_SET": "default"], set: ["CLAUDEBAR_SET": "set"])

        #expect(programs.environment(for: "/bin/sh", change)["CLAUDEBAR_SET"] == "set")
    }

    @Test
    func `should give a default to a name removed from the environment`() {
        let change = ProcessEnvironment(unset: ["HOME"], defaults: ["HOME": "/elsewhere"])

        #expect(programs.environment(for: "/bin/sh", change)["HOME"] == "/elsewhere")
    }

    @Test
    func `should count names that differ only in case as different variables`() {
        let change = ProcessEnvironment(defaults: ["home": "/lower"], set: ["path": "/lower/bin"])

        let environment = programs.environment(for: "/bin/sh", change)

        #expect(environment["home"] == "/lower")
        #expect(environment["HOME"] == home)
        #expect(environment["path"] == "/lower/bin")
        #expect(environment["PATH"] != nil)
    }
}
#endif
