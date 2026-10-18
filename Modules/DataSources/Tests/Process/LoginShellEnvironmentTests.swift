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

    private func makeShell(_ executor: any CLIExecutor) -> LoginShellEnvironment {
        LoginShellEnvironment(cliExecutor: executor, shell: FixtureShell(command: ["fixture-shell"]))
    }

    // MARK: - Name Validation

    @Test
    func `should accept conventional environment variable names`() {
        #expect(LoginShellEnvironment.isValidName("GLM_AUTH_TOKEN"))
        #expect(LoginShellEnvironment.isValidName("_PRIVATE"))
        #expect(LoginShellEnvironment.isValidName("z"))
    }

    @Test
    func `should refuse a variable name that could break out of the shell command`() {
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
    func `should find the key the user's shell profile exports`() async {
        let shell = makeShell(makeExecutor(output: markerWrapped("shell-token")))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }

    @Test
    func `should find no key when the shell profile exports it empty`() async {
        let shell = makeShell(makeExecutor(output: markerWrapped("")))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `should find no key when the login shell fails`() async {
        let shell = makeShell(makeExecutor(output: markerWrapped("partial"), exitCode: 1))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `should find no key when the login shell cannot be started`() async {
        let mock = MockCLIExecutor()
        given(mock).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willThrow(UsageError.executionFailed("shell failed"))
        let shell = makeShell(mock)
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `should never ask the shell for a variable whose name is unsafe`() async {
        let executor = makeExecutor(output: "shell-token")
        let shell = makeShell(executor)
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN; rm -rf /") == nil)
        verify(executor).execute(binary: .any, args: .any, input: .any, timeout: .any,
                                 workingDirectory: .any, autoResponses: .any).called(0)
    }

    @Test
    func `should find the key without the whitespace around it`() async {
        let shell = makeShell(makeExecutor(output: markerWrapped("  shell-token  ")))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }

    @Test
    func `should find the key when the shell profile prints a greeting first`() async {
        let output = "Welcome to zsh\n" + markerWrapped("shell-token")
        let shell = makeShell(makeExecutor(output: output))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == "shell-token")
    }

    @Test
    func `should find no key when the variable is unset and the shell profile prints a greeting`() async {
        let output = "Welcome to zsh\n" + markerWrapped("")
        let shell = makeShell(makeExecutor(output: output))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `should find no key when the shell's answer is not the one ClaudeBar asked for`() async {
        let shell = makeShell(makeExecutor(output: "shell-token\n"))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
    }

    @Test
    func `should not start a shell when no command was supplied`() async {
        let executor = makeExecutor(output: markerWrapped("shell-token"))
        let shell = LoginShellEnvironment(cliExecutor: executor, shell: FixtureShell(command: []))
        #expect(await shell.value(ofEnvVar: "GLM_TOKEN") == nil)
        verify(executor).execute(binary: .any, args: .any, input: .any, timeout: .any,
                                 workingDirectory: .any, autoResponses: .any).called(0)
    }

}

/// A login shell whose command is `command`, then the variable's name.
private struct FixtureShell: LoginShell {
    let command: [String]
    func command(printing variable: String, between begin: String, and end: String) -> [String] {
        command.isEmpty ? [] : command + [variable]
    }
}
