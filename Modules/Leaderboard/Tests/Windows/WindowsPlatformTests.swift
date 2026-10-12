#if os(Windows)
import Foundation
import Testing
@testable import Leaderboard

/// Windows' connections (MODULAR_DESIGN §10, phase 3): the key in Credential
/// Manager, and the person reading about this PC, not a Mac.
@Suite
struct WindowsPlatformTests {
    /// A credential of its own, so a test never touches a member's key.
    private let store = CredentialManagerSigningKeyStore(target: "com.tddworks.claudebar/test-\(UUID().uuidString)")

    @Test func `should keep a key in Credential Manager, where another store reads it, until it is deleted`() {
        defer { store.delete() }
        let first = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let second = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })

        store.save(first)
        let readFirst = CredentialManagerSigningKeyStore(target: store.target).load()
        store.save(second)
        let readSecond = CredentialManagerSigningKeyStore(target: store.target).load()
        store.delete()

        #expect(readFirst == first)
        #expect(readSecond == second)
        #expect(store.load() == nil)
    }

    @Test func `should have no key when none was saved, and delete nothing quietly`() {
        #expect(store.load() == nil)
        store.delete()
        #expect(store.load() == nil)
    }

    @Test func `should call this machine a PC, never a Mac, in everything the person reads`() {
        let label = DeviceLabel("Windows PC")!
        let errors: [LeaderboardError] = [
            .usernameTaken, .notShareable("claude"), .nothingShared, .notJoined, .alreadyJoined, .keyNotKept, .keyCopied, .approvedByStranger, .deviceLeftBehind(DeviceKey("k2"), ours: true), .deviceLeftBehind(DeviceKey("k2"), ours: false), .notOffered,
            .unauthorized, .removed(by: DeviceRef(publicKey: DeviceKey("k1"), label: label)), .codeExpired,
            .unknownCode, .deviceLimit, .deviceTooNew, .lastDevice, .unreachable,
        ]

        for error in errors {
            #expect(!(error.errorDescription ?? "").contains("Mac"), "\(error)")
        }
        #expect(LeaderboardError.alreadyJoined.errorDescription == "This PC is already on the leaderboard.")
    }

    @Test func `should read this PC's hardware UUID from its firmware as a UUID, or nothing`() {
        let uuid = WindowsMachineIdentity().hardwareUUID

        if let uuid {
            #expect(UUID(uuidString: uuid) != nil, "\(uuid)")
            #expect(uuid == uuid.uppercased())
        }
    }
}
#endif
