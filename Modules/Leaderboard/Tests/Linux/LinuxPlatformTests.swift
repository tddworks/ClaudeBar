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
}
#endif