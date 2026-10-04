import Testing
import Foundation
import Mockable
@testable import DataSources
import Quotas

@Suite("LoginShellEnvironment Tests")
struct LoginShellEnvironmentTests {

    // MARK: - Test Helpers

    private func makeExecutor(output: String, exitCode: Int32 = 0) -> MockCLIExecutor {
        let mock = MockCLIExecutor()
        given(mock).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: output, exitCode: exitCode))
        return mock
    }

    // MARK: - Name Validation

    @Test
    func `accepts conventional environment variable names`() {
        #expect(LoginShellEnvironment.isValidName("GLM_AUTH_TOKEN"))
        #expect(LoginShellEnvironment.isValidName("_PRIVATE"))
        #expect(LoginShellEnvironment.isValidName("z"))
    }

    @Test
    func `rejects names that could break out of the command string`() {
        #expect(!LoginShellEnvironment.isValidName(""))
        #expect(!LoginShellEnvironment.isValidName("9TOKEN"))
        #expect(!LoginShellEnvironment.isValidName("GLM;rm -rf /"))
        #expect(!LoginShellEnvironment.isValidName("GLM TOKEN"))
        #expect(!LoginShellEnvironment.isValidName("GLM$(touch /tmp/pwned)"))
        #expect(!LoginShellEnvironment.isValidName("GLM`id`"))
        #expect(!LoginShellEnvironment.isValidName("GLM_TOKÉN"))
        #expect(!LoginShellEnvironment.isValidName("TOKEN٣"))
    }

    // MARK: - Value Resolution

    private func markerWrapped(_ value: String) -> String {
        "\(LoginShellEnvironment.beginMarker)\(value)\(LoginShellEnvironment.endMarker)\n"
    }

    @Test
    func `returns the value reported by the executor`() async {
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: markerWrapped("shell-token")))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }

    @Test
    func `returns nil when the shell reports the variable as empty`() async {
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: markerWrapped("")))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `returns nil when the shell exits non-zero`() async {
        let shell = LoginShellEnvironment(
            cliExecutor: makeExecutor(output: markerWrapped("partial"), exitCode: 1)
        )
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `returns nil when the executor throws`() async {
        let mock = MockCLIExecutor()
        given(mock).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willThrow(UsageError.executionFailed("shell failed"))
        let shell = LoginShellEnvironment(cliExecutor: mock)
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `rejects invalid names without consulting the shell`() async {
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: "shell-token"))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN; rm -rf /") == nil)
    }

    @Test
    func `trims whitespace inside the markers`() async {
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: markerWrapped("  shell-token  ")))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }

    @Test
    func `extracts the value between markers when rc files print noise first`() async {
        let output = "Welcome to zsh\n" + markerWrapped("shell-token")
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: output))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }

    @Test
    func `returns nil when the variable is unset but rc noise was printed`() async {
        let output = "Welcome to zsh\n" + markerWrapped("")
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: output))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `returns nil when markers are missing from the output`() async {
        let shell = LoginShellEnvironment(cliExecutor: makeExecutor(output: "shell-token\n"))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `expands the variable in an interactive login shell`() async {
        let mock = MockCLIExecutor()
        given(mock).execute(
            binary: .any,
            args: .matching { args in
                args.contains("-i") && args.contains { $0.contains("\"$GLM_TOKEN\"") }
            },
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: markerWrapped("shell-token"), exitCode: 0))

        let shell = LoginShellEnvironment(cliExecutor: mock)
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }
}
