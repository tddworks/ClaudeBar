import Foundation
import Testing
@testable import DataSources

/// A Keychain item another CLI keeps: found by its service and, when several
/// logins share one, its account; a go-keyring item's password is stored as
/// `go-keyring-base64:<base64>` and read as what it encodes.
@Suite
struct KeychainItemTests {
    private func item(_ json: String) throws -> KeychainCredential {
        try JSONDecoder().decode(KeychainCredential.self, from: Data(json.utf8))
    }

    private func read(_ json: String, from keychain: InMemoryKeychain) throws -> Credential? {
        try KeychainReader(item: try item(json), keychain: keychain).find()?.credential
    }

    @Test func `should read the token a go-keyring password encodes`() throws {
        let encoded = "go-keyring-base64:" + Data("gho_abc123".utf8).base64EncodedString()
        let credential = try read(#"{"service":"gh:github.com","token":"$","encoding":"goKeyringBase64"}"#,
                                  from: InMemoryKeychain(service: "gh:github.com", password: encoded))
        #expect(credential?["token"] == "gho_abc123")
    }

    @Test func `should read a go-keyring item stored plain as it is`() throws {
        let credential = try read(#"{"service":"gh:github.com","token":"$","encoding":"goKeyringBase64"}"#,
                                  from: InMemoryKeychain(service: "gh:github.com", password: "gho_plain"))
        #expect(credential?["token"] == "gho_plain")
    }

    @Test func `should read the keychain item of the named account when several logins share a service`() throws {
        let keychain = InMemoryKeychain([
            .init(service: "gh:github.com", account: "octocat"): "octocat-token",
            .init(service: "gh:github.com", account: nil): "active-token",
        ])
        let credential = try read(#"{"service":"gh:github.com","account":"octocat","token":"$"}"#, from: keychain)
        #expect(credential?["token"] == "octocat-token")
    }

    @Test func `should answer a raw token that is all hex digits as it is, never as the bytes it would spell`() throws {
        let credential = try read(#"{"service":"tool","token":"$"}"#, from: InMemoryKeychain(service: "tool", password: "616263"))
        #expect(credential?["token"] == "616263")
    }

    @Test func `should save a renewed login with no account to the item it was read from, and read it back`() throws {
        let password = #"{"login":{"accessToken":"old-token","expiresAt":1000}}"#
        let keychain = InMemoryKeychain(service: "Some-credentials", password: password)
        let reader = KeychainReader(
            item: try item(#"{"service":"Some-credentials","token":"$.login.accessToken","expiresAt":"$.login.expiresAt"}"#),
            keychain: keychain
        )
        let found = try #require(try reader.find())
        var refreshed = found.credential
        refreshed["token"] = "new-token"
        refreshed["expiresAt"] = "2000"

        found.save?(refreshed)

        #expect(keychain.saves == [.init(service: "Some-credentials", account: nil)])
        #expect(keychain.all.count == 1)
        let reread = try #require(try reader.find())
        #expect(reread.credential["token"] == "new-token")
        #expect(reread.credential["expiresAt"] == "2000")
    }

    @Test func `should never rewrite an item another tool's library encodes`() throws {
        let encoded = "go-keyring-base64:" + Data(#"{"token":"old"}"#.utf8).base64EncodedString()
        let keychain = InMemoryKeychain(service: "gemini", account: "antigravity", password: encoded)
        let found = try #require(try KeychainReader(
            item: try item(#"{"service":"gemini","account":"antigravity","encoding":"goKeyringBase64","token":"$.token"}"#),
            keychain: keychain
        ).find())
        var refreshed = found.credential
        refreshed["token"] = "new"

        found.save?(refreshed)

        #expect(keychain.saves.isEmpty)
    }

    @Test func `should keep a keychain item's account and encoding apart from its key, and when written out and read back`() throws {
        let item = try item(#"{"service":"gh:github.com","account":"octocat","encoding":"goKeyringBase64","token":"$"}"#)
        #expect(item.fields == ["token": "$"])
        #expect(item.account == "octocat")
        #expect(try JSONDecoder().decode(KeychainCredential.self, from: JSONEncoder().encode(item)) == item)
    }
}
