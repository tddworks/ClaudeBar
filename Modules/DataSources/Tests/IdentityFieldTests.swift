import DataSources
import Foundation
import Testing

/// A field that identifies a login — the credential's account id, or the email
/// a context file holds — written as the mapping writes paths, and decoded
/// once into what it points at.
@Suite
struct IdentityFieldTests {
    private func identity(_ field: String) throws -> Identity {
        try JSONDecoder().decode(Identity.self, from: Data(#"{"field":"\#(field)","equals":"x"}"#.utf8))
    }

    @Test
    func `a bare name is a credential value, as before`() throws {
        #expect(try identity("account").field == .credential("account"))
    }

    @Test
    func `a credential path names a credential value`() throws {
        #expect(try identity("$credential.account").field == .credential("account"))
    }

    @Test
    func `a context path names a field of a context file`() throws {
        #expect(try identity("$context.account.email").field == .context(file: "account", field: "email"))
    }

    @Test
    func `a context path without a field is refused on load`() {
        #expect(throws: DecodingError.self) { try identity("$context.account") }
    }

    @Test
    func `a field writes back the way it was read`() throws {
        for field in ["account", "$context.account.email"] {
            let encoded = try JSONEncoder().encode(try identity(field))
            #expect(try JSONDecoder().decode(Identity.self, from: encoded) == identity(field))
            #expect(String(decoding: encoded, as: UTF8.self).contains(field))
        }
    }
}
