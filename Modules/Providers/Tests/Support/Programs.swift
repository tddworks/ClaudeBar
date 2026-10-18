import Foundation
import Mockable
@testable import DataSources

extension MockProcesses {
    /// A platform's programs, each run on what `runner` answers for its
    /// environment, a CLI found as that runner finds it, and a conversation
    /// that answers nothing.
    static func running(_ runner: @escaping @Sendable (ProcessEnvironment) -> any CLIExecutor) -> MockProcesses {
        let processes = MockProcesses()
        given(processes).runner(.any).willProduce(runner)
        given(processes).locate(.any).willProduce { runner(ProcessEnvironment()).locate($0) }
        given(processes).converse(.any, .any, .any, .any).willReturn(MockRPCTransport())
        return processes
    }
}
