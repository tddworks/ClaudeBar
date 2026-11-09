import Foundation
import Testing

/// The test program started again, as a second process of the app writing the
/// same log: on Windows the app and its hourly `claudebar-upload.exe` both
/// write `ClaudeBar.log`. The second process runs one test, named for it, which
/// reads its job from its environment.
enum SecondProcess {
    /// Write `lines` tagged lines in each of `rounds` rounds, each round to
    /// `<folder>/<round>/ClaudeBar.log`, starting a new file past
    /// `maxFileSize`. In each round's folder the process says it is ready
    /// (`ready-<tag>`) and waits for the first process to say go (`go`), so
    /// both write at once.
    struct Job {
        let folder: URL
        let tag: String
        let lines: Int
        var rounds = 1
        var maxFileSize = 5 * 1024 * 1024

        func log(_ round: Int) -> URL { folder.appending(path: "\(round)/ClaudeBar.log") }
        func ready(_ round: Int) -> URL { folder.appending(path: "\(round)/ready-\(tag)") }
        func go(_ round: Int) -> URL { folder.appending(path: "\(round)/go") }
    }

    private static let key = "CLAUDEBAR_SECOND_PROCESS"

    /// The test program, where it is a program of its own, as `swift test`
    /// builds it on Linux and Windows. On the Mac the tests run inside a host
    /// (`xctest`, Xcode's agent) that can't be started again for one test.
    static var program: URL? {
        guard let url = Bundle.main.executableURL, url.pathExtension == "xctest" else { return nil }
        return url
    }

    /// What this process was started to do, when it is a second process.
    static var job: Job? {
        guard let value = ProcessInfo.processInfo.environment[key] else { return nil }
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, let lines = Int(parts[2]), let rounds = Int(parts[3]),
              let maxFileSize = Int(parts[4]) else { return nil }
        return Job(folder: URL(fileURLWithPath: parts[0], isDirectory: true), tag: parts[1], lines: lines,
                   rounds: rounds, maxFileSize: maxFileSize)
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
        let value = [job.folder.path, job.tag, String(job.lines), String(job.rounds), String(job.maxFileSize)]
            .joined(separator: "|")
        process.environment = ProcessInfo.processInfo.environment.merging([key: value]) { $1 }
        process.standardOutput = printed
        process.standardError = printed
        try process.run()
        try printed.close()
        return process
    }

    /// Starts each round once every job is ready for it, and waits for the
    /// processes to end. Answers whether every round started.
    static func run(_ jobs: [Job], _ processes: [Process]) -> Bool {
        var started = true
        for round in 0..<(jobs.first?.rounds ?? 0) where started {
            started = wait(for: jobs.map { $0.ready(round) }, seconds: 120)
            FileManager.default.createFile(atPath: jobs[0].go(round).path, contents: nil)
        }
        processes.forEach { $0.waitUntilExit() }
        return started
    }

    /// Waits up to `seconds` for every file in `files` to exist.
    static func wait(for files: [URL], seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.001)
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
