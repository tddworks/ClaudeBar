import Foundation

/// Programs started over and over while a test saves, as the app starts them
/// while it saves: a CLI read, and the Windows client's `wsl.exe` and
/// `schtasks.exe`. Each is started with `Foundation.Process`, which on Windows
/// hands the program every handle the app may pass on.
enum StartingPrograms {
    /// Runs `work` on a thread of its own while four threads start a short
    /// program over and over, and answers what it returned once the last
    /// program has ended. Its own thread keeps the work off the cooperative
    /// pool the other tests run on. The same as DataSources' tests' own copy.
    static func meanwhile<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Thread {
                let starting = Switch()
                let starters = DispatchGroup()
                for _ in 0..<4 {
                    starters.enter()
                    Thread.detachNewThread {
                        while starting.isOn { startOne() }
                        starters.leave()
                    }
                }
                let result = Result { try work() }
                starting.turnOff()
                starters.wait()
                continuation.resume(with: result)
            }.start()
        }
    }

    /// Starts a program that ends at once, and waits for it.
    private static func startOne() {
        let program = Process()
        #if os(Windows)
        program.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ComSpec"] ?? #"C:\Windows\System32\cmd.exe"#)
        program.arguments = ["/c", "exit"]
        #else
        program.executableURL = URL(fileURLWithPath: "/bin/sh")
        program.arguments = ["-c", ":"]
        #endif
        program.standardOutput = FileHandle.nullDevice
        program.standardError = FileHandle.nullDevice
        if (try? program.run()) != nil { program.waitUntilExit() }
    }

    private final class Switch: @unchecked Sendable {
        private let lock = NSLock()
        private var on = true

        var isOn: Bool {
            lock.lock()
            defer { lock.unlock() }
            return on
        }

        func turnOff() {
            lock.lock()
            on = false
            lock.unlock()
        }
    }
}
