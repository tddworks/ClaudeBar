import Diagnostics
import Foundation

/// `command` — one fixed, read-only command whose JSON answer holds the
/// records: a tool whose logs are a database it can query itself (`opencode
/// db "<sql>" --format json`). The answer is one JSON array, each element
/// read by the first shape whose `where` holds. A platform that runs no
/// commands, a missing CLI, a failed run, or an answer that is not a JSON
/// array is an empty read, as an unreadable file is.
struct CommandLogReader: Sendable {
    private let call: CommandCall
    private let shapes: [RecordShape]
    private let run: (@Sendable (ProcessEnvironment) -> any CLIExecutor)?
    private let directory: @Sendable () -> URL?

    init(call: CommandCall, shapes: [RecordShape], run: (@Sendable (ProcessEnvironment) -> any CLIExecutor)?,
         platform: Platform, homeDirectory: URL, environment: @escaping @Sendable (String) -> String?) {
        self.call = call
        self.shapes = shapes
        self.run = run
        // Resolve the trusted directory only when the command actually starts.
        self.directory = { call.workingDirectory.map { _ in
            cliWorkingDirectory(platform: platform, homeDirectory: homeDirectory, environment: environment)
        } }
    }

    func records() async -> [LogRecord] {
        guard let run else {
            AppLog.probes.info("Usage history: \(call.cli) cannot run here, so its log reads empty")
            return []
        }
        let executor = run(call.environment)
        guard executor.locate(call.cli) != nil else {
            AppLog.probes.info("Usage history: \(call.cli) is not installed, so its log reads empty")
            return []
        }
        let result: CLIResult
        do {
            result = try await executor.execute(binary: call.cli, args: call.args, input: call.input,
                                                timeout: call.timeout, workingDirectory: directory(), autoResponses: [:])
        } catch {
            AppLog.probes.error("Usage history: \(call.cli) could not start")
            return []
        }
        guard result.exitCode == 0 else {
            AppLog.probes.error("Usage history: \(call.cli) exited with \(result.exitCode)")
            return []
        }
        guard let answer = try? JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [Any] else {
            AppLog.probes.error("Usage history: \(call.cli) printed no JSON array, so its log reads empty")
            return []
        }
        return answer.compactMap { shapes.record(from: $0) }
    }
}
