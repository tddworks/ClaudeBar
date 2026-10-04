import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// File-based logger that writes to ~/Library/Logs/ClaudeBar/ClaudeBar.log
/// Provides user-accessible logs for debugging and support.
///
/// Thread-safety: All file operations are serialized on a dedicated dispatch queue.
/// The class is marked `Sendable` because:
/// - `fileURL` and `maxFileSize` are immutable after init
/// - `queue` is a serial queue that serializes all mutable state access
/// - Timestamp formatting happens inside the serial queue
public final class FileLogger: @unchecked Sendable {
    public static let shared = FileLogger()
    
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.tddworks.ClaudeBar.FileLogger")
    private let maxFileSize: UInt64 = 5 * 1024 * 1024  // 5MB
    
    /// The directory containing log files
    public var logsDirectory: URL {
        fileURL.deletingLastPathComponent()
    }
    
    private init() {
        // ~/Library/Logs/ClaudeBar/ClaudeBar.log
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("ClaudeBar", isDirectory: true)
        
        // Create directory if needed
        // Note: Can't use AppLog here as FileLogger is used by AppLog (circular dependency)
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            NSLog("[FileLogger] Failed to create logs directory at %@: %@", logsDir.path, error.localizedDescription)
        }
        
        self.fileURL = logsDir.appendingPathComponent("ClaudeBar.log")
    }
    
    /// Creates a thread-safe timestamp string.
    /// Called only from within the serial queue.
    private func timestamp() -> String {
        // ISO8601DateFormatter is thread-safe, but we create a new formatter
        // each time to avoid any potential issues and keep the code simple.
        // Performance impact is negligible for logging frequency.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
    
    /// Log levels matching OSLog conventions
    public enum Level: String, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }
    
    /// Write a log entry to the file
    public func log(_ level: Level, category: String, message: String) {
        queue.async { [self] in
            rotateIfNeeded()
            
            let ts = timestamp()
            let line = "[\(ts)] [\(level.rawValue)] [\(category)] \(message)\n"
            
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        defer { try? handle.close() }
                        handle.seekToEndOfFile()
                        handle.write(data)
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }
    }
    
    /// Rotate log file if it exceeds max size
    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else {
            return
        }
        
        // Rotate: rename current to .old, start fresh
        let oldURL = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: fileURL, to: oldURL)
    }
    
    /// Open the logs directory in Finder
    public func openLogsDirectory() {
        NSWorkspace.shared.open(logsDirectory)
    }

    /// Open the current log file in TextEdit
    public func openCurrentLogFile() {
        NSWorkspace.shared.open(fileURL)
    }
}
