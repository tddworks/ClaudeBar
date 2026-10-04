import CryptoKit
import Foundation
import Mockable

/// The key made on join. Its private half never leaves this Mac and is never
/// logged; the server holds only `publicKey`, which can check a signature
/// but never make one.
public struct SigningKey: Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey

    public static func generate() -> SigningKey {
        SigningKey(privateKey: Curve25519.Signing.PrivateKey())
    }

    public init(rawRepresentation: Data) throws {
        privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    private init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    /// The private half, for the key store only.
    public var rawRepresentation: Data { privateKey.rawRepresentation }

    /// The public half, base64url without padding — what `POST /join` sends.
    public var publicKey: String { privateKey.publicKey.rawRepresentation.base64URLEncoded }

    func signature(for message: Data) throws -> Data {
        try privateKey.signature(for: message)
    }
}

/// Where this Mac keeps the private half of its key.
@Mockable
public protocol SigningKeyStore: Sendable {
    func load() -> Data?
    func save(_ rawKey: Data)
    func delete()
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
