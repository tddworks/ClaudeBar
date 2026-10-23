#if canImport(Darwin) || canImport(Glibc)
import Quotas
import Foundation
import Testing
@testable import DataSources

/// The terminal runner says a CLI it can't find is `cliNotFound` (#198).
@Suite(.needsTerminal)
struct DefaultCLIExecutorMissingTests {
    @Test
    func `should report the CLI as not found when it isn't installed`() async throws {
        let executor = DefaultCLIExecutor(installed: PlatformTerminal.installed, terminal: PlatformTerminal.terminal)

        await #expect(throws: UsageError.cliNotFound("claudebar-no-such-cli")) {
            _ = try await executor.execute(binary: "claudebar-no-such-cli", args: [], input: nil, timeout: 1,
                                           workingDirectory: nil, autoResponses: [:])
        }
    }
}
#endif
