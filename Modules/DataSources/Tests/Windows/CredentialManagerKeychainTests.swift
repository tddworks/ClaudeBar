#if os(Windows)
import Foundation
import Testing
import WinSDK
@testable import DataSources

/// Windows' secret store is Credential Manager, asked as go-keyring asks it
/// (the GitHub CLI's library): a generic credential named `service:account`,
/// `service:` when there is no account, its blob the password's UTF-8 bytes.
/// Each test uses a service of its own and removes what it made.
@Suite
struct CredentialManagerKeychainTests {
    private let service = "com.tddworks.claudebar/test-\(UUID().uuidString)"
    private let keychain = CredentialManagerKeychain()

    @Test func `should keep a password, overwrite it, and read each back`() {
        defer { Self.delete(service + ":octocat") }

        let first = keychain.save("first", service: service, account: "octocat")
        let readFirst = keychain.password(service: service, account: "octocat")
        let second = keychain.save("second ✓", service: service, account: "octocat")
        let readSecond = keychain.password(service: service, account: "octocat")

        #expect(first && second)
        #expect(readFirst == "first")
        #expect(readSecond == "second ✓")
    }

    @Test func `should find no password for a name that isn't there`() {
        #expect(keychain.password(service: service, account: nil) == nil)
        #expect(keychain.password(service: service, account: "nobody") == nil)
    }

    @Test func `should read an item the way go-keyring writes one: named service colon, no user, raw bytes`() throws {
        defer { Self.delete(service + ":") }
        try Self.write(target: service + ":", userName: nil, blob: Array("gho_token".utf8))

        #expect(keychain.password(service: service, account: nil) == "gho_token")
        #expect(keychain.password(service: service, account: "octocat") == nil)
    }

    @Test func `should save a login with no account over the item it was read from, with no second one made`() throws {
        defer { Self.delete(service + ":") }
        try Self.write(target: service + ":", userName: nil, blob: Array(#"{"token":"old"}"#.utf8))
        let reader = KeychainReader(item: KeychainCredential(service: service, fields: ["token": "$.token"]), keychain: keychain)

        let found = try #require(try reader.find())
        var refreshed = found.credential
        refreshed["token"] = "new"
        found.save?(refreshed)

        #expect(try reader.find()?.credential["token"] == "new")
        #expect(Self.targets(startingWith: service) == [service + ":"])
    }

    @Test func `should keep every change when several threads change items at once`() {
        let prefix = service + "-"
        defer { for name in Self.targets(startingWith: prefix) { Self.delete(name) } }

        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            for round in 0..<20 {
                let item = prefix + "\(thread)-\(round)"
                _ = keychain.save("first", service: item, account: "octocat")
                _ = keychain.save("second", service: item, account: "octocat")
                Self.delete(item + ":octocat")
            }
        }

        #expect(Self.targets(startingWith: prefix).isEmpty)
    }

    // MARK: - Credential Manager, asked directly, one call at a time as the store asks it

    private static func write(target: String, userName: String?, blob: [UInt8]) throws {
        var name = Array(target.utf16) + [0]
        var user = userName.map { Array($0.utf16) + [0] }
        var bytes = blob
        let written = name.withUnsafeMutableBufferPointer { name in
            bytes.withUnsafeMutableBufferPointer { bytes in
                withOptionalBuffer(&user) { user in
                    var credential = CREDENTIALW()
                    credential.`Type` = DWORD(CRED_TYPE_GENERIC)
                    credential.TargetName = name.baseAddress
                    credential.UserName = user
                    credential.CredentialBlobSize = DWORD(bytes.count)
                    credential.CredentialBlob = bytes.baseAddress
                    credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                    return CredentialManager.oneAtATime { CredWriteW(&credential, 0) }
                }
            }
        }
        try #require(written, "CredWriteW failed with \(GetLastError())")
    }

    private static func withOptionalBuffer<T>(_ buffer: inout [UInt16]?, _ body: (UnsafeMutablePointer<UInt16>?) -> T) -> T {
        guard buffer != nil else { return body(nil) }
        return buffer!.withUnsafeMutableBufferPointer { body($0.baseAddress) }
    }

    private static func delete(_ target: String) {
        _ = CredentialManager.oneAtATime {
            target.withCString(encodedAs: UTF16.self) { CredDeleteW($0, DWORD(CRED_TYPE_GENERIC), 0) }
        }
    }

    private static func targets(startingWith prefix: String) -> [String] {
        var count: DWORD = 0
        var credentials: UnsafeMutablePointer<PCREDENTIALW?>?
        let found = CredentialManager.oneAtATime {
            (prefix + "*").withCString(encodedAs: UTF16.self) { CredEnumerateW($0, 0, &count, &credentials) }
        }
        guard found, let credentials else { return [] }
        defer { CredFree(credentials) }
        return (0..<Int(count)).compactMap { credentials[$0]?.pointee.TargetName.map { String(decodingCString: $0, as: UTF16.self) } }
    }
}
#endif
