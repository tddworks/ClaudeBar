import Foundation
import Testing
@testable import DataSources

/// A Keychain item another CLI keeps: found by its service and, when several
/// logins share one, its account; a go-keyring item's password is stored as
/// `go-keyring-base64:<base64>` and read as what it encodes.
@Suite
struct KeychainItemTests {
    final class Calls: @unchecked Sendable { var arguments: [[String]] = [] }

    private func read(_ json: String, password: String, calls: Calls = Calls()) throws -> Credential? {
        let item = try JSONDecoder().decode(KeychainCredential.self, from: Data(json.utf8))
        return try KeychainReader(item: item, security: { arguments in
            calls.arguments.append(arguments)
            return (0, password)
        }).find()?.credential
    }

    @Test func `a go-keyring password is read as what it encodes`() throws {
        let encoded = "go-keyring-base64:" + Data("gho_abc123".utf8).base64EncodedString()
        let credential = try read(#"{"service":"gh:github.com","token":"$","encoding":"goKeyringBase64"}"#, password: encoded)
        #expect(credential?["token"] == "gho_abc123")
    }

    @Test func `a go-keyring item stored plain is read as it is`() throws {
        let credential = try read(#"{"service":"gh:github.com","token":"$","encoding":"goKeyringBase64"}"#, password: "gho_plain")
        #expect(credential?["token"] == "gho_plain")
    }

    @Test func `an account narrows which item is read`() throws {
        let calls = Calls()
        _ = try read(#"{"service":"gh:github.com","account":"octocat","token":"$"}"#, password: "t", calls: calls)
        #expect(calls.arguments.first == ["find-generic-password", "-s", "gh:github.com", "-a", "octocat", "-w"])
    }

    @Test func `account and encoding are not credential fields, and round-trip`() throws {
        let item = try JSONDecoder().decode(KeychainCredential.self,
            from: Data(#"{"service":"gh:github.com","account":"octocat","encoding":"goKeyringBase64","token":"$"}"#.utf8))
        #expect(item.fields == ["token": "$"])
        #expect(item.account == "octocat")
        #expect(try JSONDecoder().decode(KeychainCredential.self, from: JSONEncoder().encode(item)) == item)
    }
}
