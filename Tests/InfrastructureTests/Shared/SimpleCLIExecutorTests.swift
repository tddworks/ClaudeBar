import Testing
import Foundation
@testable import Infrastructure

@Suite
struct SimpleCLIExecutorTests {

    // MARK: - PATH Augmentation
    //
    // Menu bar apps launched by launchd get a minimal PATH; script CLIs
    // with `/usr/bin/env` shebangs (bun/node) need their runtime findable.

    @Test
    func `augmented PATH contains the binary's own directory`() {
        let env = SimpleCLIExecutor.augmentedEnvironment(binaryPath: "/test-omp-home/.bun/bin/omp")
        let entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        // The runtime (bun) usually lives next to the tool it runs.
        #expect(entries.filter { $0 == "/test-omp-home/.bun/bin" }.count == 1)
    }

    @Test
    func `augmented PATH keeps existing entries in front and appends common dirs`() {
        let env = SimpleCLIExecutor.augmentedEnvironment(binaryPath: "/usr/bin/true")
        let entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        if let currentFirst = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").first.map(String.init) {
            #expect(entries.first == currentFirst)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(entries.contains("\(home)/.bun/bin"))
        #expect(entries.contains("\(home)/.local/bin"))
    }

    @Test
    func `augmented PATH does not duplicate directories it appends`() {
        let env = SimpleCLIExecutor.augmentedEnvironment(binaryPath: "/opt/homebrew/bin/tool")
        let entries = (env["PATH"] ?? "").split(separator: ":").map(String.init)

        // /opt/homebrew/bin is both the binary dir and a common path —
        // it must be appended at most once beyond any ambient occurrence.
        let ambient = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        let ambientCount = ambient.filter { $0 == "/opt/homebrew/bin" }.count
        let augmentedCount = entries.filter { $0 == "/opt/homebrew/bin" }.count
        #expect(augmentedCount == max(ambientCount, 1))
    }
}
