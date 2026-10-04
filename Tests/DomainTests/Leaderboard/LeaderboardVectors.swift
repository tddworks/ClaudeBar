import Foundation

/// `vectors.json` beside this file: the username rule and the signing cases.
/// The server (tddworks/claudebar-server) checks an identical copy, so the two
/// sides can't drift apart: change both together.
struct LeaderboardVectors: Decodable {
    struct Usernames: Decodable {
        let valid: [String]
        let invalid: [String]
    }

    struct Signing: Decodable {
        struct Case: Decodable {
            let method: String
            let pathAndQuery: String
            let timestamp: Int
            let nonce: String
            let body: String
            let canonical: String
            let signature: String
        }

        let privateKey: String
        let publicKey: String
        let cases: [Case]
    }

    let usernames: Usernames
    let signing: Signing

    static func load(filePath: String = #filePath) throws -> LeaderboardVectors {
        let url = URL(fileURLWithPath: filePath).deletingLastPathComponent().appendingPathComponent("vectors.json")
        return try JSONDecoder().decode(LeaderboardVectors.self, from: Data(contentsOf: url))
    }
}

extension Data {
    init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
