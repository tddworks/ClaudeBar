import Foundation

/// The file log, for people: `[time] [LEVEL] [category] message`, one line
/// each, every level but `debug` (`notice` as `INFO`). Past `maxFileSize` the
/// file becomes `<name>.old.log` and a new one starts.
///
/// Lines are appended on a serial queue, so a log call never waits on the
/// disk; it is `@unchecked Sendable` because that queue is the only place its
/// file is touched in this process. Another process may write the same file;
/// `LogFile` lets the OS put each line at its end.
final class FileLogSink: LogSink, @unchecked Sendable {
    let fileURL: URL
    private let maxFileSize: Int
    private let queue = DispatchQueue(label: "com.tddworks.ClaudeBar.FileLogSink")

    init(fileURL: URL, maxFileSize: Int = 5 * 1024 * 1024) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        // Not through AppLog: this sink is how AppLog writes.
        let folder = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSLog("[FileLogSink] Failed to create logs directory at %@: %@", folder.path, error.localizedDescription)
        }
    }

    func write(_ level: LogLevel, category: String, message: String) {
        guard let label = Self.label(level) else { return }
        queue.async { [self] in
            rotateIfNeeded()
            let line = "[\(Self.timestamp())] [\(label)] [\(category)] \(message)\n"
            do {
                try LogFile.append(Data(line.utf8), to: fileURL)
            } catch {
                // Not through AppLog: this sink is how AppLog writes.
                NSLog("[FileLogSink] Failed to write to %@ (%@): %@", fileURL.path, error.localizedDescription, line)
            }
        }
    }

    /// Waits until every line written so far is in the file.
    func flush() {
        queue.sync {}
    }

    private static func label(_ level: LogLevel) -> String? {
        switch level {
        case .debug: nil
        case .info, .notice: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func rotateIfNeeded() {
        guard isPastItsSize() else { return }
        // Another process writing this log may be starting a new file at the
        // same moment: one at a time, and only if the file is still past its
        // size on this one's turn, so neither throws away the file the other
        // just kept as `.old.log`.
        do {
            try LogFile.rotating(fileURL) {
                guard isPastItsSize() else { return }
                let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: fileURL, to: old)
            }
        } catch {
            // Not through AppLog: this sink is how AppLog writes. The file
            // stays as it is; the next line tries again.
            NSLog("[FileLogSink] Couldn't start a new log file at %@: %@", fileURL.path, error.localizedDescription)
        }
    }

    private func isPastItsSize() -> Bool {
        // A fresh URL each time: a URL keeps the resource values it has read.
        guard let size = try? URL(filePath: fileURL.path).resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > maxFileSize
    }
}
