#if os(Linux)
import Foundation
import Testing
@testable import Leaderboard

/// Linux' connections (MODULAR_DESIGN §10): the key in the person's secret
/// store through libsecret, with the app's own store behind it, and the person
/// reading about this machine, not a Mac and not a PC.
///
/// Serialized: the last test puts a `secret-tool` of its own on `PATH`, which
/// is the whole process's `PATH` for as long as it runs.
@Suite(.serialized)
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
    /// `secret-tool` of the test's own on `PATH` answers `store`, `lookup` and
    /// `clear` from a file, so the key is really handed to a tool on its
    /// standard input and read back from that tool. A CI runner, having no
    /// secret service, would otherwise only ever exercise the fallback.
    @Test func `should keep the key in the secret tool and read the same key back`() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claudebar-secret-tool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        defer {
            try? FileManager.default.removeItem(at: folder)
            setenv("PATH", path, 1)
            unsetenv("CLAUDEBAR_TEST_SECRET_FILE")
        }
        let tool = folder.appendingPathComponent("secret-tool")
        try """
        #!/bin/sh
        case "$1" in
          store) cat > "$CLAUDEBAR_TEST_SECRET_FILE" ;;
          lookup) cat "$CLAUDEBAR_TEST_SECRET_FILE" 2>/dev/null ;;
          clear) rm -f "$CLAUDEBAR_TEST_SECRET_FILE" ;;
        esac
        """.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        setenv("CLAUDEBAR_TEST_SECRET_FILE", folder.appendingPathComponent("kept").path, 1)
        setenv("PATH", folder.path + ":" + path, 1)

        let store = SecretToolSigningKeyStore(account: "com.tddworks.claudebar/test-\(UUID().uuidString)")
        let key = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        store.save(key)
        #expect(store.load() == key)

        store.delete()
        #expect(store.load() == nil)
    }
}
#endif
