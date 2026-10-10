import Crypto
import Foundation

/// Signs a request the way the Worker checks it: over the method, the path
/// and query, the time, a nonce and the body's SHA-256, joined by newlines.
/// The server verifies the exact bytes it received, so the body signed here
/// must be the body sent. Pinned by `Modules/Leaderboard/Tests/vectors.json`,
/// which the server checks an identical copy of.
public enum RequestSigner {
    public static func canonical(method: String, pathAndQuery: String, timestamp: Int, nonce: String, body: Data) -> String {
        let hash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return [method, pathAndQuery, String(timestamp), nonce, hash].joined(separator: "\n")
    }

    /// The headers of a signed request. `X-Key` names the device's key, which is
    /// how the server finds the device and, through it, the member; `X-Member`
    /// stays for a server from before devices, which finds the member by name,
    /// and is left out by a new device still waiting for approval, which has
    /// none. Neither is part of the signed string, so the shared vectors don't change.
    public static func headers(member: Username?, key: SigningKey, method: String, pathAndQuery: String, body: Data,
                               timestamp: Int, nonce: String) throws -> [String: String] {
        let message = canonical(method: method, pathAndQuery: pathAndQuery, timestamp: timestamp, nonce: nonce, body: body)
        let signature = try key.signature(for: Data(message.utf8))
        var headers = [
            "X-Key": key.publicKey,
            "X-Timestamp": String(timestamp),
            "X-Nonce": nonce,
            "X-Signature": signature.base64URLEncoded
        ]
        headers["X-Member"] = member?.value
        return headers
    }

    /// Sixteen random bytes, base64url: a signed request is accepted once.
    public static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return Data(bytes).base64URLEncoded
    }
}
