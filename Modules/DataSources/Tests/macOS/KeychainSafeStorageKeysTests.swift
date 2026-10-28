#if os(macOS)
import Foundation
import Testing
@testable import DataSources

/// The Mac opens what an Electron app sealed with Chromium's scheme: the key
/// stretched from the app's Keychain item, AES-128-CBC behind `v10`. The
/// sealed value is OpenSSL's, made outside this code:
/// `openssl enc -aes-128-cbc -K <PBKDF2-SHA1(password, saltysalt, 1003)> -iv 20…20`.
@Suite
struct KeychainSafeStorageKeysTests {
    final class Keychain: KeychainItems, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        let stored: String?
        init(_ stored: String?) { self.stored = stored }
        var services: [String] { lock.withLock { asked } }
        func password(service: String, account: String?) -> String? {
            lock.withLock { asked.append(service) }
            return stored
        }
        func save(_ password: String, service: String, account: String?) -> Bool { false }
    }

    private let sealed = Data(base64Encoded: "djEwTmyZUS7gzDUWgy1Kfz+8QhIGk1swaOA1drVzUtsMmFCPk4xa0VCMtjn2NovW8WK86m8mpHwMGbbmq8+tkdVKhw==")!
    private let token = "header.eyJzdWIiOiJnaXRodWJ8dXNlcl8wMUZJWFRVUkUifQ.signature"

    @Test
    func `should open a value sealed with the key in the app's Keychain item`() throws {
        let keychain = Keychain("fixture-safe-storage-password\n")
        let keys = KeychainSafeStorageKeys(keychain: keychain)

        let key = try keys.key(app: "Cursor")
        let plain = try #require(keys.open(sealed, with: key))

        #expect(keychain.services == ["Cursor Safe Storage"])
        #expect(String(decoding: plain, as: UTF8.self) == token)
    }

    @Test
    func `should name the Keychain item when the app has none or it can't be read`() {
        let keys = KeychainSafeStorageKeys(keychain: Keychain(nil))

        #expect(throws: SafeStorageKeyUnreadable(place: "Keychain “Cursor Safe Storage”")) {
            try keys.key(app: "Cursor")
        }
    }
}
#endif
