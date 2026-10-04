import Foundation

/// `Server/leaderboard/test/vectors.json`: the username rule and the signing
/// cases the Worker's suite checks too, so the two sides can't drift apart.
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
        let repo = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("Server/leaderboard/test/vectors.json")
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
