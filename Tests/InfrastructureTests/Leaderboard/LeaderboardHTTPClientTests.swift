import CryptoKit
import Foundation
import Mockable
import Testing
@testable import Domain
@testable import Infrastructure

@Suite
struct LeaderboardHTTPClientTests {
    static let host = URL(string: "https://leaderboard.test")!
    static let now = Date(timeIntervalSince1970: 1_791_080_000)

    private let key = SigningKey.generate()
    private var member: MemberCredentials { MemberCredentials(username: Username("tokenwhale")!, key: key) }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: host, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    /// A client whose one answer is `status` with `body`; `sent` receives the request it made.
    private func client(status: Int = 200, body: String = "{}", sent: ((URLRequest) -> Void)? = nil) -> LeaderboardHTTPClient {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            sent?(request)
            return (Data(body.utf8), Self.response(status))
        }
        return LeaderboardHTTPClient(networkClient: network, host: Self.host, now: { Self.now })
    }

    private func failing(_ error: Error) -> LeaderboardHTTPClient {
        let network = MockNetworkClient()
        given(network).request(.any).willThrow(error)
        return LeaderboardHTTPClient(networkClient: network, host: Self.host, now: { Self.now })
    }

    private func isSigned(_ request: URLRequest, by key: SigningKey) throws -> Bool {
        let url = try #require(request.url)
        let pathAndQuery = url.path + (url.query.map { "?" + $0 } ?? "")
        let message = RequestSigner.canonical(
            method: try #require(request.httpMethod), pathAndQuery: pathAndQuery,
            timestamp: Int(try #require(request.value(forHTTPHeaderField: "X-Timestamp")))!,
            nonce: try #require(request.value(forHTTPHeaderField: "X-Nonce")), body: request.httpBody ?? Data())
        let signature = try #require(request.value(forHTTPHeaderField: "X-Signature").flatMap { Data(base64URL: $0) })
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: #require(Data(base64URL: key.publicKey)))
        return publicKey.isValidSignature(signature, for: Data(message.utf8))
    }

    // MARK: - Join

    @Test func `joining sends the name and the public key, unsigned`() async throws {
        var sent: URLRequest?
        try await client(status: 201, sent: { sent = $0 }).join(username: "tokenwhale", publicKey: key.publicKey)

        let body = try JSONSerialization.jsonObject(with: #require(sent?.httpBody)) as? [String: String]
        #expect(sent?.url?.absoluteString == "https://leaderboard.test/join")
        #expect(sent?.httpMethod == "POST")
        #expect(body == ["username": "tokenwhale", "publicKey": key.publicKey])
        #expect(sent?.value(forHTTPHeaderField: "X-Signature") == nil)
    }

    @Test func `a taken name is said so`() async {
        await #expect(throws: LeaderboardError.usernameTaken) {
            try await client(status: 409, body: #"{"error":"usernameTaken","message":"That username is taken."}"#)
                .join(username: "tokenwhale", publicKey: key.publicKey)
        }
    }

    // MARK: - Upload

    @Test func `an upload carries this Mac's date and the days, signed over the exact body sent`() async throws {
        var sent: URLRequest?
        let days = [DailyTokens(provider: "claude", day: "2026-10-04", input: 1, output: 2, cacheWrite: 3, cacheRead: 4, unsplit: 0)]

        try await client(sent: { sent = $0 }).upload(days, as: member)

        let request = try #require(sent)
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
        #expect(request.url?.path == "/usage")
        #expect(request.httpMethod == "PUT")
        #expect(body?["today"] as? String == DailyTokens.day(of: Self.now))
        #expect((body?["days"] as? [[String: Any]])?.first?["cacheRead"] as? Int == 4)
        #expect(request.value(forHTTPHeaderField: "X-Member") == "tokenwhale")
        #expect(try isSigned(request, by: key))
    }

    // MARK: - Reading

    @Test func `your own data is a signed read of the view`() async throws {
        var sent: URLRequest?
        let body = #"{"username":"tokenwhale","visible":false,"standing":{"rank":3,"username":"tokenwhale","total":90,"input":10,"output":20,"cache":60,"byProvider":{"claude":90}},"days":[{"provider":"claude","day":"2026-10-04","input":10,"output":20,"cacheWrite":0,"cacheRead":60,"unsplit":0}]}"#

        let summary = try await client(body: body, sent: { sent = $0 })
            .me(in: BoardView(period: .sevenDays, provider: "claude"), as: member)

        let request = try #require(sent)
        #expect(request.url?.query == "period=7d&provider=claude")
        #expect(try isSigned(request, by: key))
        #expect(summary.visible == false)
        #expect(summary.standing?.rank == 3)
        #expect(summary.days.count == 1)
    }

    @Test func `the board is read without signing`() async throws {
        var sent: URLRequest?
        let body = #"{"period":"today","provider":null,"standings":[{"rank":1,"username":"big","total":1000,"input":500,"output":0,"cache":500,"byProvider":{"claude":1000}}]}"#

        let standings = try await client(body: body, sent: { sent = $0 }).board(in: BoardView(period: .today))

        #expect(sent?.url?.query == "period=today")
        #expect(sent?.value(forHTTPHeaderField: "X-Signature") == nil)
        // The board is cacheable for the web page; the app must see it fresh.
        #expect(sent?.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(standings == [Standing(rank: 1, username: "big", total: 1000, input: 500, cache: 500, byProvider: ["claude": 1000])])
    }

    // MARK: - Changes

    @Test func `hiding and renaming are one signed patch`() async throws {
        var sent: URLRequest?
        try await client(sent: { sent = $0 }).update(MemberChange(username: "whale2", visible: false), as: member)

        let request = try #require(sent)
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
        #expect(request.httpMethod == "PATCH")
        #expect(body?["username"] as? String == "whale2")
        #expect(body?["visible"] as? Bool == false)
        #expect(body?["shareCountry"] == nil)
        #expect(try isSigned(request, by: key))
    }

    @Test func `opting in to the globe sends only that change`() async throws {
        var sent: URLRequest?
        try await client(sent: { sent = $0 }).update(MemberChange(sharesCountry: true), as: member)

        let body = try JSONSerialization.jsonObject(with: #require(sent?.httpBody)) as? [String: Any]
        #expect(body?.keys.sorted() == ["shareCountry"])
        #expect(body?["shareCountry"] as? Bool == true)
    }

    @Test func `the globe is read without signing, countries and the hidden count`() async throws {
        var sent: URLRequest?
        let body = #"{"period":"30d","provider":null,"countries":[{"country":"NL","members":3,"tokens":300}],"hiddenCountries":2}"#

        let globe = try await client(body: body, sent: { sent = $0 }).globe(in: BoardView(period: .thirtyDays))

        #expect(sent?.url?.path == "/globe")
        #expect(sent?.url?.query == "period=30d")
        #expect(sent?.value(forHTTPHeaderField: "X-Signature") == nil)
        #expect(globe == GlobeSummary(countries: [.init(country: "NL", members: 3, tokens: 300)], hiddenCountries: 2))
    }

    @Test func `your own data says whether your country is on the globe`() async throws {
        let body = #"{"username":"tokenwhale","visible":true,"shareCountry":true,"country":"NL","standing":null,"days":[]}"#
        let summary = try await client(body: body).me(in: BoardView(period: .sevenDays), as: member)
        #expect(summary.sharesCountry)
        #expect(summary.country == "NL")
    }

    @Test func `leaving is a signed delete`() async throws {
        var sent: URLRequest?
        try await client(sent: { sent = $0 }).leave(as: member)

        #expect(sent?.httpMethod == "DELETE")
        #expect(try isSigned(#require(sent), by: key))
    }

    // MARK: - Failures

    @Test func `a refused signature means the key no longer matches`() async {
        await #expect(throws: LeaderboardError.unauthorized) {
            try await client(status: 401, body: #"{"error":"unauthorized","message":"no"}"#).leave(as: member)
        }
    }

    @Test func `a refusal the server explains is shown in its words`() async {
        await #expect(throws: LeaderboardError.rejected("This Mac's clock is more than five minutes off.")) {
            try await client(status: 401, body: #"{"error":"clock","message":"This Mac's clock is more than five minutes off."}"#)
                .leave(as: member)
        }
        await #expect(throws: LeaderboardError.rejected("a day can't be in the future")) {
            try await client(status: 400, body: #"{"error":"badDay","message":"a day can't be in the future"}"#).upload([], as: member)
        }
    }

    @Test func `a server error or no connection means unreachable`() async {
        await #expect(throws: LeaderboardError.unreachable) {
            try await client(status: 503, body: "oops").board(in: BoardView(period: .today))
        }
        await #expect(throws: LeaderboardError.unreachable) {
            try await failing(URLError(.notConnectedToInternet)).board(in: BoardView(period: .today))
        }
    }
}

extension Data {
    init?(base64URL text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
