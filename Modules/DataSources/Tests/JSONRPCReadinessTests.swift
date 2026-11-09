import Foundation
import Mockable
import Synchronization
import Testing
@testable import DataSources

/// Whether a JSON-RPC CLI is there is asked at every refresh, twice on
/// Windows. A CLI that isn't installed is no failure: the login is skipped and
/// another data source may answer. The log says so once, and again only after
/// the CLI was found and went missing (#693).
@Suite
struct JSONRPCReadinessTests {
    /// A machine where the CLI is installed while `installed` says so.
    final class Machine: Sendable {
        let installed = Mutex(false)

        var processes: Processes {
            let cli = MockCLIExecutor()
            given(cli).locate(.any).willProduce { [self] name in self.installed.withLock { $0 } ? "/usr/local/bin/\(name)" : nil }
            return .running { _ in cli }
        }
    }

    private func fetcher(on machine: Machine, log: LogLines) throws -> JSONRPCFetcher {
        let call = try JSONDecoder().decode(JSONRPCCall.self, from: Data(#"{"cli":"codex","args":["app-server"],"call":"read"}"#.utf8))
        return JSONRPCFetcher(call: call, processes: machine.processes, directory: { nil }, log: log.logger)
    }

    @Test func `should say once, not at every refresh, that a CLI isn't installed`() throws {
        let log = LogLines()
        let fetcher = try fetcher(on: Machine(), log: log)

        for _ in 0..<3 { #expect(!fetcher.isReady()) }

        #expect(log.inTheFile == ["'codex' not found in PATH"])
        #expect(log.errors.isEmpty)
    }

    @Test func `should say again that a CLI isn't installed after it was found and went missing`() throws {
        let log = LogLines()
        let machine = Machine()
        let fetcher = try fetcher(on: machine, log: log)

        _ = fetcher.isReady()
        machine.installed.withLock { $0 = true }
        #expect(fetcher.isReady())
        machine.installed.withLock { $0 = false }
        _ = fetcher.isReady()

        #expect(log.inTheFile == ["'codex' not found in PATH", "'codex' not found in PATH"])
    }
}
