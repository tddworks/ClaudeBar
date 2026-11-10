import Foundation
import Testing
@testable import Diagnostics

/// The file log a person opens and attaches to an issue: the same lines on
/// the Mac and on Windows.
@Suite
struct FileLogSinkTests {
    private let folder = FileManager.default.temporaryDirectory
        .appending(path: "FileLogSinkTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private var file: URL { folder.appending(path: "Logs/ClaudeBar.log") }

    private func lines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test
    func `should create the log's folder on first use`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = FileLogSink(fileURL: file)

        sink.write(.info, category: "monitor", message: "started")
        sink.flush()

        #expect(try lines(of: file).count == 1)
    }

    @Test
    func `should write each line with its time, level and category, in the order written`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = FileLogSink(fileURL: file)

        sink.write(.info, category: "probes", message: "Starting probe")
        sink.write(.warning, category: "network", message: "Slow answer")
        sink.write(.error, category: "probes", message: "Probe failed")
        sink.flush()

        let lines = try lines(of: file)
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix("] [INFO] [probes] Starting probe"))
        #expect(lines[1].hasSuffix("] [WARNING] [network] Slow answer"))
        #expect(lines[2].hasSuffix("] [ERROR] [probes] Probe failed"))
        let time = try #require(lines[0].split(separator: "]").first?.dropFirst())
        #expect((try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(String(time))) != nil)
    }

    @Test
    func `should keep debug lines out of the file and write a notice as info`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = FileLogSink(fileURL: file)

        sink.write(.debug, category: "ui", message: "Only for developers")
        sink.write(.notice, category: "ui", message: "Attached to the status item")
        sink.flush()

        let lines = try lines(of: file)
        #expect(lines.count == 1)
        #expect(lines[0].hasSuffix("] [INFO] [ui] Attached to the status item"))
    }

    @Test
    func `should start a new file once the log passes its size, keeping the last one beside it`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = FileLogSink(fileURL: file, maxFileSize: 100)

        sink.write(.info, category: "monitor", message: String(repeating: "a", count: 120))
        sink.write(.info, category: "monitor", message: "after the rotation")
        sink.flush()

        let old = folder.appending(path: "Logs/ClaudeBar.old.log")
        #expect(try lines(of: old).count == 1)
        #expect(try lines(of: old)[0].hasSuffix(String(repeating: "a", count: 120)))
        #expect(try lines(of: file).count == 1)
        #expect(try lines(of: file)[0].hasSuffix("] [INFO] [monitor] after the rotation"))
    }

    /// On Windows a program the app starts inherits what the app has open at
    /// that moment, as the Windows client's `schtasks.exe` and any program
    /// started with `Foundation.Process` do. A new log's first line still
    /// reaches the file.
    @Test(.startsPrograms)
    func `should write a new log's first line while the app starts programs`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let folder = folder

        let lost = try await StartingPrograms.meanwhile {
            (0..<300).filter { index in
                let file = folder.appending(path: "Logs/\(index).log")
                let sink = FileLogSink(fileURL: file)
                sink.write(.info, category: "monitor", message: "first line")
                sink.flush()
                return (try? String(contentsOf: file, encoding: .utf8))?.hasSuffix("] [INFO] [monitor] first line\n") != true
            }.count
        }

        #expect(lost == 0)
    }

    /// Two of the app's processes write one log, each in its own order: on
    /// Windows the app and its hourly upload. Neither's line takes the
    /// other's place or breaks into it.
    @Test(.startsPrograms, .startsSecondProcess)
    func `should keep every line whole when two of the app's processes write the log at once`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let jobs = ["A", "B"].map { SecondProcess.Job(folder: folder, tag: $0, lines: 2000) }

        let processes = try start(jobs)
        let started = try SecondProcess.run(jobs, processes)

        #expect(started)
        #expect(processes.map(\.terminationStatus) == [0, 0])
        let expected = Set(jobs.flatMap { job in (0..<job.lines).map { "\(job.tag) \($0)" } })
        let written = try lines(of: jobs[0].log(0)).map(Self.message)
        let lost = expected.subtracting(written).count
        let broken = written.filter { !expected.contains($0) }.count
        let twice = written.count - Set(written).count
        #expect(lost == 0)
        #expect(broken == 0)
        #expect(twice == 0)
    }

    /// The log keeps one earlier file, so a line older than one new file is
    /// gone by design. When both processes pass the size at once, one starts
    /// the new file and neither throws away the file the other just kept:
    /// in a round that starts one new file, every line of both is still there.
    @Test(.startsPrograms, .startsSecondProcess)
    func `should lose no line to the other process when both start a new file as they write the log at once`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        // A line is 50 bytes: the 12 lines pass 300 once, after three or four from each.
        let jobs = ["A", "B"].map { SecondProcess.Job(folder: folder, tag: $0, lines: 6, rounds: 300, maxFileSize: 300) }

        let processes = try start(jobs)
        let started = try SecondProcess.run(jobs, processes)

        #expect(started)
        #expect(processes.map(\.terminationStatus) == [0, 0])
        let expected = Set(jobs.flatMap { job in (0..<job.lines).map { "\(job.tag) \($0)" } })
        var lost = 0, broken = 0, twice = 0, newFiles = 0
        for round in 0..<jobs[0].rounds {
            let current = jobs[0].log(round)
            let earlier = current.deletingPathExtension().appendingPathExtension("old.log")
            if FileManager.default.fileExists(atPath: earlier.path) { newFiles += 1 }
            let written = ((try? lines(of: earlier)) ?? []).map(Self.message) + ((try? lines(of: current)) ?? []).map(Self.message)
            lost += expected.subtracting(written).count
            broken += written.filter { !expected.contains($0) }.count
            twice += written.count - Set(written).count
        }
        #expect(lost == 0)
        #expect(broken == 0)
        #expect(twice == 0)
        #expect(newFiles == jobs[0].rounds)
    }

    /// The other half of the tests above: a second process writes its lines
    /// in each round, once the first says go.
    @Test(.asSecondProcess)
    func `should write its lines to the log, as a second process of the app`() throws {
        let job = try #require(SecondProcess.job)
        for round in 0..<job.rounds {
            let sink = FileLogSink(fileURL: job.log(round), maxFileSize: job.maxFileSize)
            try SecondProcess.make(job.ready(round))
            try #require(SecondProcess.wait(for: [job.go(round)], seconds: 120))

            for index in 0..<job.lines {
                sink.write(.info, category: "processes", message: "\(job.tag) \(index)")
            }
            sink.flush()
        }
    }

    private func start(_ jobs: [SecondProcess.Job]) throws -> [Process] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try jobs.map {
            try SecondProcess.start(running: "as a second process of the app", job: $0,
                                    output: folder.appending(path: "second-process-\($0.tag).txt"))
        }
    }

    /// A line's message, after its time, level and category; the whole line
    /// if it has none.
    private static func message(_ line: String) -> String {
        line.range(of: "] [INFO] [processes] ").map { String(line[$0.upperBound...]) } ?? line
    }
}
