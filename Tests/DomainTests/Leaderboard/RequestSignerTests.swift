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

    @Test func `the public key is the one the server is given`() throws {
        #expect(try key().publicKey == LeaderboardVectors.load().signing.publicKey)
    }

    @Test func `the signed text is method, path, time, nonce and the body's hash`() throws {
        for item in try LeaderboardVectors.load().signing.cases {
            let canonical = RequestSigner.canonical(method: item.method, pathAndQuery: item.pathAndQuery,
                                                    timestamp: item.timestamp, nonce: item.nonce, body: Data(item.body.utf8))
            #expect(canonical == item.canonical)
        }
    }

    @Test func `each request carries a signature the public key accepts`() throws {
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

    @Test func `a signature made elsewhere checks out here too`() throws {
        let vectors = try LeaderboardVectors.load()
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64URL: vectors.signing.publicKey)))
        for item in vectors.signing.cases {
            let signature = try #require(Data(base64URL: item.signature))
            #expect(publicKey.isValidSignature(signature, for: Data(item.canonical.utf8)))
        }
    }

    @Test func `a fresh nonce is sixteen random bytes`() {
        let first = RequestSigner.makeNonce()
        #expect(Data(base64URL: first)?.count == 16)
        #expect(first != RequestSigner.makeNonce())
    }

    @Test func `a key survives being stored and read back`() throws {
        let key = SigningKey.generate()
        #expect(try SigningKey(rawRepresentation: key.rawRepresentation).publicKey == key.publicKey)
    }
}
