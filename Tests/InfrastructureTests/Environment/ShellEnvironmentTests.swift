import Testing
import Foundation
import Mockable
import DataSources
@testable import Infrastructure

/// A variable the app was launched without is still found in the user's login
/// shell (#170), and a found value is not asked for again.
@Suite
struct ShellEnvironmentTests {
    private func shell(answering value: String?, calls: Calls = Calls()) -> MockCLIExecutor {
        let executor = MockCLIExecutor()
        given(executor).execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { _, _, _, _, _, _ in
                calls.count += 1
                return CLIResult(output: "@@CLAUDEBAR_BEGIN@@\(value ?? "")@@CLAUDEBAR_END@@", exitCode: 0)
            }
        return executor
    }

    final class Calls: @unchecked Sendable { var count = 0 }

    @Test
    func `the app's own environment answers first`() {
        let calls = Calls()
        let environment = ShellEnvironment(process: ["GLM_KEY": "from-process"], cliExecutor: shell(answering: "from-shell", calls: calls))
        #expect(environment.value("GLM_KEY") == "from-process")
        #expect(calls.count == 0)
    }

    @Test
    func `a variable only the login shell exports is read from it once`() {
        let calls = Calls()
        let environment = ShellEnvironment(process: [:], cliExecutor: shell(answering: "from-shell", calls: calls))
        #expect(environment.value("GLM_KEY") == "from-shell")
        #expect(environment.value("GLM_KEY") == "from-shell")
        #expect(calls.count == 1)
    }

    @Test
    func `a variable set nowhere is nil and asked again later`() {
        let calls = Calls()
        let environment = ShellEnvironment(process: [:], cliExecutor: shell(answering: nil, calls: calls))
        #expect(environment.value("GLM_KEY") == nil)
        #expect(environment.value("GLM_KEY") == nil)
        #expect(calls.count == 2)
    }
}
