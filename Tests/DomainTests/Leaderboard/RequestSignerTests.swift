import CryptoKit
import Foundation
import Testing
@testable import Domain

@Suite
struct RequestSignerTests {
    private func key() throws -> SigningKey {
        let vectors = try LeaderboardVectors.load()
        return try SigningKey(rawRepresentation: #require(Data(base64URL: vectors.signing.privateKey)))
    }

    @Test func `should give the server the public key the shared vectors expect`() throws {
        #expect(try key().publicKey == LeaderboardVectors.load().signing.publicKey)
    }

    @Test func `should sign the method, path, time, nonce and the body's hash, as the server checks them`() throws {
        for item in try LeaderboardVectors.load().signing.cases {
            let canonical = RequestSigner.canonical(method: item.method, pathAndQuery: item.pathAndQuery,
                                                    timestamp: item.timestamp, nonce: item.nonce, body: Data(item.body.utf8))
            #expect(canonical == item.canonical)
        }
    }

    @Test func `should sign each request so the server accepts it for the member`() throws {
        let vectors = try LeaderboardVectors.load()
        let key = try key()
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64URL: vectors.signing.publicKey)))
        for item in vectors.signing.cases {
            let headers = try RequestSigner.headers(
                member: #require(Username("tokenwhale")), key: key, method: item.method, pathAndQuery: item.pathAndQuery,
                body: Data(item.body.utf8), timestamp: item.timestamp, nonce: item.nonce)

            // CryptoKit's Ed25519 signatures are randomised, so they're checked, not compared.
            let signature = try #require(headers["X-Signature"].flatMap { Data(base64URL: $0) })
            #expect(publicKey.isValidSignature(signature, for: Data(item.canonical.utf8)))
            #expect(headers["X-Member"] == "tokenwhale")
            #expect(headers["X-Timestamp"] == String(item.timestamp))
            #expect(headers["X-Nonce"] == item.nonce)
        }
    }

    @Test func `should name the device's key on each signed request, so the server finds the device by it`() throws {
        let vectors = try LeaderboardVectors.load()
        for item in vectors.signing.cases {
            let headers = try RequestSigner.headers(
                member: #require(Username("tokenwhale")), key: key(), method: item.method, pathAndQuery: item.pathAndQuery,
                body: Data(item.body.utf8), timestamp: item.timestamp, nonce: item.nonce)

            #expect(headers["X-Key"] == vectors.signing.publicKey)
        }
    }

    @Test func `should accept a signature the server's own vectors made`() throws {
        let vectors = try LeaderboardVectors.load()
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64URL: vectors.signing.publicKey)))
        for item in vectors.signing.cases {
            let signature = try #require(Data(base64URL: item.signature))
            #expect(publicKey.isValidSignature(signature, for: Data(item.canonical.utf8)))
        }
    }

    @Test func `should make every nonce sixteen fresh random bytes`() {
        let first = RequestSigner.makeNonce()
        #expect(Data(base64URL: first)?.count == 16)
        #expect(first != RequestSigner.makeNonce())
    }

    @Test func `should keep this Mac's key the same once it is stored and read back`() throws {
        let key = SigningKey.generate()
        #expect(try SigningKey(rawRepresentation: key.rawRepresentation).publicKey == key.publicKey)
    }
}
