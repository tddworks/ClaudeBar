#if os(Linux)
import Foundation
import Testing
@testable import Leaderboard

/// Linux' connections (MODULAR_DESIGN §10): the key in the person's secret
/// store through libsecret, with the app's own store behind it, and the person
/// reading about this machine, not a Mac and not a PC.
@Suite
struct LinuxPlatformTests {
    /// A store of its own, so a test never touches a member's key. The secret
    /// store is asked first and the app's own store keeps it when libsecret
    /// isn't there — a container, a bare CI runner — which is the case this
    /// also covers.
    private func store() -> FallbackSigningKeyStore {
        FallbackSigningKeyStore(
            secure: SecretToolSigningKeyStore(account: "com.tddworks.claudebar/test-\(UUID().uuidString)"),
            fallback: DefaultsSigningKeyStore(
                defaults: UserDefaults(suiteName: "com.tddworks.claudebar.test-\(UUID().uuidString)")!
            )
        )
    }

    @Test func `should keep a key where another store reads it, until it is deleted`() {
        let store = store()
        defer { store.delete() }
        let first = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let second = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        store.save(first)
        #expect(store.load() == first)
        store.save(second)
        #expect(store.load() == second)

        store.delete()
        #expect(store.load() == nil)
    }

    @Test func `should have no key when none was saved, and delete nothing quietly`() {
        let store = store()
        #expect(store.load() == nil)
        store.delete()
        #expect(store.load() == nil)
    }

    @Test func `should call this machine a Linux machine, never a Mac or a PC, in everything the person reads`() {
        let label = DeviceLabel("Linux")!
        let errors: [LeaderboardError] = [
            .usernameTaken, .notShareable("claude"), .nothingShared, .notJoined, .alreadyJoined, .keyNotKept, .keyCopied, .approvedByStranger, .deviceLeftBehind(DeviceKey("k2"), ours: true), .deviceLeftBehind(DeviceKey("k2"), ours: false), .notOffered,
            .unauthorized, .removed(by: DeviceRef(publicKey: DeviceKey("k1"), label: label)), .codeExpired,
            .unknownCode, .deviceLimit, .deviceTooNew, .lastDevice, .unreachable,
        ]

        for error in errors {
            let text = error.errorDescription ?? ""
            #expect(!text.contains("Mac"), "\(error)")
            #expect(!text.contains("PC"), "\(error)")
        }
    }

    /// The secret store's own path, not the fallback it hides behind: a
    /// `secret-tool` of the test's own answers `store`, `lookup` and `clear`
    /// from a file, so the key is really handed to a tool on its standard input
    /// and read back from that tool. A CI runner, having no secret service,
    /// would otherwise only ever exercise the fallback. The store is pointed
    /// at the tool: the process' `PATH` stays as it is, since `setenv` while
    /// other tests read the environment can crash them.
    @Test func `should keep the key in the secret tool and read the same key back`() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudebar-secret-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appendingPathComponent("secret-tool")
        let kept = folder.appendingPathComponent("kept").path
        try Self.writeExecutable("""
        #!/bin/sh
        case "$1" in
          store) cat > '\(kept)' ;;
          lookup) cat '\(kept)' 2>/dev/null ;;
          clear) rm -f '\(kept)' ;;
        esac
        """, to: tool)

        var store = SecretToolSigningKeyStore(account: "com.tddworks.claudebar/test-\(UUID().uuidString)")
        store.tool = tool.path
        let key = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        store.save(key)
        #expect(store.load() == key)

        store.delete()
        #expect(store.load() == nil)
    }

    /// Writes a tool the test then runs, through a short-lived `sh`, never this
    /// process: a child another test starts while this process holds the file
    /// open for writing keeps that handle until it execs, and running the
    /// file meanwhile fails with `ETXTBSY`. DataSources' tests write theirs
    /// the same way (`ExecutableFile`).
    private static func writeExecutable(_ text: String, to url: URL) throws {
        let arguments = ["/bin/sh", "-c", #"printf '%s' "$2" > "$1" && chmod 755 "$1""#, "sh", url.path, text]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        // A fixed environment: the writer needs only `PATH`.
        let envp: [UnsafeMutablePointer<CChar>?] = [strdup("PATH=/usr/bin:/bin"), nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, "/bin/sh", nil, nil, argv, envp)
        guard spawned == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EIO) }
        var status: Int32 = 0
        var waited = waitpid(pid, &status, 0)
        while waited == -1 && errno == EINTR { waited = waitpid(pid, &status, 0) }
        // Only a reaped child's status says the file was written.
        guard waited == pid else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard status == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
    }
}
#endif
