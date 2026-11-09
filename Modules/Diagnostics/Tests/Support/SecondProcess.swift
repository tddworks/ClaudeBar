import Foundation
import Testing

/// The test program started again, as a second process of the app writing the
/// same log: on Windows the app and its hourly `claudebar-upload.exe` both
/// write `ClaudeBar.log`. The second process runs one test, named for it, which
/// reads from its environment which log to write, with which tag, how many
/// lines, and the folder where it says it's ready and waits to be told to go.
enum SecondProcess {
    struct Job {
        let log: URL
        let tag: String
        let lines: Int

        /// Where this process says it has started.
        var ready: URL { log.deletingLastPathComponent().appending(path: "ready-\(tag)") }
        /// Where the first process says to start writing.
        var go: URL { log.deletingLastPathComponent().appending(path: "go") }
    }

    private static let logKey = "CLAUDEBAR_SECOND_PROCESS_LOG"
    private static let tagKey = "CLAUDEBAR_SECOND_PROCESS_TAG"
    private static let linesKey = "CLAUDEBAR_SECOND_PROCESS_LINES"

    /// The test program, where it is a program of its own, as `swift test`
    /// builds it on Linux and Windows. On the Mac the tests run inside a host
    /// (`xctest`, Xcode's agent) that can't be started again for one test.
    static var program: URL? {
        guard let url = Bundle.main.executableURL, url.pathExtension == "xctest" else { return nil }
        return url
    }

    /// What this process was started to do, when it is a second process.
    static var job: Job? {
        let environment = ProcessInfo.processInfo.environment
        guard let log = environment[logKey], let tag = environment[tagKey],
              let lines = environment[linesKey].flatMap(Int.init) else { return nil }
        return Job(log: URL(fileURLWithPath: log), tag: tag, lines: lines)
    }

    /// Starts the test program again to run only the tests whose names
    /// contain `test`, doing `job`; what it prints goes to `output`.
    static func start(running test: String, job: Job, output: URL) throws -> Process {
        guard let program else { throw CocoaError(.executableNotLoadable) }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let printed = try FileHandle(forWritingTo: output)
        let process = Process()
        process.executableURL = program
        process.arguments = ["--testing-library", "swift-testing", "--filter", test]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [logKey: job.log.path, tagKey: job.tag, linesKey: String(job.lines)]) { $1 }
        process.standardOutput = printed
        process.standardError = printed
        try process.run()
        try printed.close()
        return process
    }

    /// Waits up to `seconds` for every file in `files` to exist.
    static func wait(for files: [URL], seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return true
    }
}

extension Trait where Self == ConditionTrait {
    /// Runs only in a second process a test started.
    static var asSecondProcess: Self {
        .enabled(if: SecondProcess.job != nil, "runs only as the second process another test starts")
    }

    /// Starts the test program again, which needs it to be a program of its own.
    static var startsSecondProcess: Self {
        .enabled(if: SecondProcess.program != nil,
                 "the tests aren't a program of their own here (on the Mac they run inside xctest or Xcode's agent), so a second process can't be started")
    }
}
