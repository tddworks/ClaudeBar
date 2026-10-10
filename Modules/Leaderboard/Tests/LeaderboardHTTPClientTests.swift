import Crypto
import Foundation
import Mockable
import Testing
@testable import Leaderboard
import DataSources
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite
struct LeaderboardHTTPClientTests {
    static let host = URL(string: "https://leaderboard.test")!
    static let now = Date(timeIntervalSince1970: 1_791_080_000)

    private let key = SigningKey.generate()
    private var member: MemberCredentials { MemberCredentials(username: Username("tokenwhale")!, key: key) }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: host, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    static let clientName = "claudebar-macos/9.9.9"

    /// A client whose one answer is `status` with `body`; `sent` receives the request it made.
    private func client(status: Int = 200, body: String = "{}", sent: ((URLRequest) -> Void)? = nil) -> LeaderboardHTTPClient {
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { request in
            sent?(request)
            return (Data(body.utf8), Self.response(status))
        }
        return LeaderboardHTTPClient(networkClient: network, host: Self.host, client: Self.clientName, now: { Self.now })
    }

    private func failing(_ error: Error) -> LeaderboardHTTPClient {
        let network = MockNetworkClient()
        given(network).request(.any).willThrow(error)
        return LeaderboardHTTPClient(networkClient: network, host: Self.host, client: Self.clientName, now: { Self.now })
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

    @Test func `should ask to join with the name, public key and this device's label, unsigned`() async throws {
        var sent: URLRequest?
        try await client(status: 201, sent: { sent = $0 }).join(username: "tokenwhale", publicKey: key.publicKey, label: "MacBook Pro")

        let body = try JSONSerialization.jsonObject(with: #require(sent?.httpBody)) as? [String: String]
        #expect(sent?.url?.absoluteString == "https://leaderboard.test/join")
        #expect(sent?.httpMethod == "POST")
        #expect(body == ["username": "tokenwhale", "publicKey": key.publicKey, "label": "MacBook Pro"])
        #expect(sent?.value(forHTTPHeaderField: "X-Signature") == nil)
    }

    @Test func `should say the name is taken when someone already has it`() async {
        await #expect(throws: LeaderboardError.usernameTaken) {
            try await client(status: 409, body: #"{"error":"usernameTaken","message":"That username is taken."}"#)
                .join(username: "tokenwhale", publicKey: key.publicKey, label: "Mac")
        }
    }

    // MARK: - Upload

    @Test func `should upload the days with this Mac's date, signed over the exact body sent`() async throws {
        var sent: URLRequest?
        let days = [DailyTokens(provider: "claude", day: "2026-10-04", input: 1, output: 2, cacheWrite: 3, cacheRead: 4, unsplit: 0)]

        _ = try await client(sent: { sent = $0 }).upload(days, as: member)

        let request = try #require(sent)
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
        #expect(request.url?.path == "/usage")
        #expect(request.httpMethod == "PUT")
        #expect(body?["today"] as? String == DailyTokens.day(of: Self.now))
        #expect((body?["days"] as? [[String: Any]])?.first?["cacheRead"] as? Int == 4)
        #expect(request.value(forHTTPHeaderField: "X-Member") == "tokenwhale")
        #expect(try isSigned(request, by: key))
    }

    @Test func `should read the days the server refused alone, each with why`() async throws {
        let body = #"{"stored":1,"refused":[{"provider":"claude","day":"2026-10-04","reason":"cap"}]}"#

        let refused = try await client(body: body).upload([], as: member)

        #expect(refused == [RefusedDay(provider: "claude", day: "2026-10-04", reason: "cap")])
    }

    @Test func `should pass over a refused row that names no provider or day, and keep the rest`() async throws {
        let body = #"{"stored":0,"refused":[{"provider":null,"day":null,"reason":"notAnObject"},{"provider":"codex","day":"2026-10-03","reason":"future"}]}"#

        let refused = try await client(body: body).upload([], as: member)

        #expect(refused == [RefusedDay(provider: "codex", day: "2026-10-03", reason: "future")])
    }

    @Test func `should read no refused days from a server from before devices`() async throws {
        #expect(try await client(body: "").upload([], as: member).isEmpty)
        #expect(try await client(body: #"{"ok":true}"#).upload([], as: member).isEmpty)
    }

    @Test(arguments: [
        #"{"refused":"cap"}"#,
        #"{"stored":1,"refused":null}"#,
        #"{"refused":[{"provider":"claude","day":"2026-10-04"}]}"#,
        #"{"stored":1,"refused":["#,
        #"[]"#,
        #""stored""#,
    ])
    func `should fail the upload when it can't read the answer, rather than take it as no refused days`(body: String) async {
        await #expect(throws: LeaderboardError.rejected("The leaderboard answered with something unreadable.")) {
            _ = try await client(body: body).upload([], as: member)
        }
    }

    // MARK: - Naming the client

    @Test func `should name the client on every request, signed or not`() async throws {
        var sent: [URLRequest] = []
        let client = client(body: #"{"standings":[],"countries":[]}"#, sent: { sent.append($0) })

        try await client.join(username: "tokenwhale", publicKey: key.publicKey, label: "Mac")
        _ = try await client.board(period: .sevenDays, provider: nil)
        _ = try await client.globe(period: .thirtyDays)
        _ = try await client.upload([], as: member)
        try await client.leave(as: member)

        #expect(sent.count == 5)
        #expect(sent.allSatisfy { $0.value(forHTTPHeaderField: "X-Client") == Self.clientName })
    }

    // MARK: - Reading

    @Test func `should read the member's own standing and days for the chosen view, signed`() async throws {
        var sent: URLRequest?
        let body = #"{"username":"tokenwhale","visible":false,"standing":{"rank":3,"username":"tokenwhale","total":90,"input":10,"output":20,"cache":60,"byProvider":{"claude":90}},"days":[{"provider":"claude","day":"2026-10-04","input":10,"output":20,"cacheWrite":0,"cacheRead":60,"unsplit":0}]}"#

        let summary = try await client(body: body, sent: { sent = $0 })
            .me(period: .sevenDays, provider: "claude", as: member)

        let request = try #require(sent)
        #expect(request.url?.query == "period=7d&provider=claude")
        #expect(try isSigned(request, by: key))
        #expect(summary.visible == false)
        #expect(summary.onBoard?.rank == 3)
        #expect(summary.days.count == 1)
    }

    @Test func `should read the board fresh and unsigned`() async throws {
        var sent: URLRequest?
        let body = #"{"period":"today","provider":null,"standings":[{"rank":1,"username":"big","total":1000,"input":500,"output":0,"cache":500,"byProvider":{"claude":1000}}]}"#

        let standings = try await client(body: body, sent: { sent = $0 }).board(period: .today, provider: nil)

        #expect(sent?.url?.query == "period=today")
        #expect(sent?.value(forHTTPHeaderField: "X-Signature") == nil)
        // The board is cacheable for the web page; the app must see it fresh.
        #expect(sent?.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(standings == [Board.Member(rank: 1, username: "big", total: 1000, input: 500, cache: 500, byProvider: ["claude": 1000])])
    }

    // MARK: - Changes

    @Test func `should hide and rename the member in one signed change`() async throws {
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

    @Test func `should send only the globe opt-in when the member shares their country`() async throws {
        var sent: URLRequest?
        try await client(sent: { sent = $0 }).update(MemberChange(sharesCountry: true), as: member)

        let body = try JSONSerialization.jsonObject(with: #require(sent?.httpBody)) as? [String: Any]
        #expect(body?.keys.sorted() == ["shareCountry"])
        #expect(body?["shareCountry"] as? Bool == true)
    }

    @Test func `should send a profile link as platform and handle, and clear it when removed`() async throws {
        var sent: URLRequest?
        let link = try #require(ProfileLink(platform: .github, handle: "octocat"))
        try await client(sent: { sent = $0 }).update(MemberChange(link: .set(link)), as: member)
        var body = try JSONSerialization.jsonObject(with: #require(sent?.httpBody)) as? [String: Any]
        #expect(body?["link"] as? [String: String] == ["platform": "github", "handle": "octocat"])

        try await client(sent: { sent = $0 }).update(MemberChange(link: .remove), as: member)
        body = try JSONSerialization.jsonObject(with: #require(sent?.httpBody)) as? [String: Any]
        #expect(body?.keys.sorted() == ["link"])
        #expect(body?["link"] is NSNull)
    }

    @Test func `should show each member's link and drop one that breaks its platform's rules`() async throws {
        let body = #"{"standings":[{"rank":1,"username":"a","total":5,"link":{"platform":"x","handle":"jack"}},{"rank":2,"username":"b","total":3,"link":{"platform":"x","handle":"https://evil.example"}},{"rank":3,"username":"c","total":1}]}"#

        let standings = try await client(body: body).board(period: .sevenDays, provider: nil)

        #expect(standings.map(\.link?.handle) == ["jack", nil, nil])
    }

    @Test func `should read every country on the globe, unsigned`() async throws {
        var sent: URLRequest?
        let body = #"{"period":"30d","provider":null,"countries":[{"country":"NL","members":3,"tokens":300}],"present":["GR","VN"],"hiddenCountries":2}"#

        let globe = try await client(body: body, sent: { sent = $0 }).globe(period: .thirtyDays)

        #expect(sent?.url?.path == "/globe")
        #expect(sent?.url?.query == "period=30d")
        #expect(sent?.value(forHTTPHeaderField: "X-Signature") == nil)
        #expect(globe == GlobeSummary(countries: [.init(country: "NL", members: 3, tokens: 300)], present: ["GR", "VN"]))
    }

    @Test func `should show only the countries with numbers when the server doesn't name the others`() async throws {
        let body = #"{"period":"30d","provider":null,"countries":[{"country":"NL","members":3,"tokens":300}],"hiddenCountries":2}"#

        let globe = try await client(body: body).globe(period: .thirtyDays)

        #expect(globe == GlobeSummary(countries: [.init(country: "NL", members: 3, tokens: 300)], present: []))
    }

    @Test func `should tell the member whether their country is on the globe`() async throws {
        let body = #"{"username":"tokenwhale","visible":true,"shareCountry":true,"country":"NL","standing":null,"days":[]}"#
        let summary = try await client(body: body).me(period: .sevenDays, provider: nil, as: member)
        #expect(summary.sharesCountry)
        #expect(summary.country == "NL")
    }

    @Test func `should leave the leaderboard with a signed request`() async throws {
        var sent: URLRequest?
        try await client(sent: { sent = $0 }).leave(as: member)

        #expect(sent?.httpMethod == "DELETE")
        #expect(try isSigned(#require(sent), by: key))
    }

    // MARK: - Devices (§2a)

    @Test func `should ask to add this device with its key and label, unsigned, and read the code it shows`() async throws {
        var sent: URLRequest?
        let body = #"{"code":"WDJBMJHT","expiresIn":600,"interval":5}"#

        let authorization = try await client(status: 201, body: body, sent: { sent = $0 })
            .requestDevice(publicKey: key.publicKey, label: "Mac mini")

        let request = try #require(sent)
        let sentBody = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(request.url?.path == "/devices")
        #expect(request.httpMethod == "POST")
        #expect(sentBody == ["publicKey": key.publicKey, "label": "Mac mini"])
        #expect(request.value(forHTTPHeaderField: "X-Signature") == nil)
        #expect(authorization == DeviceAuthorization(code: try #require(DeviceCode("WDJB-MJHT")), expiresIn: 600, interval: 5))
    }

    @Test func `should ask whether this device was approved signed with its own key, naming no member`() async throws {
        var sent: URLRequest?

        let approval = try await client(status: 202, body: #"{"waiting":true,"expiresIn":540}"#, sent: { sent = $0 })
            .approval(of: key)

        let request = try #require(sent)
        #expect(approval == .waiting)
        #expect(request.url?.path == "/me")
        #expect(request.value(forHTTPHeaderField: "X-Key") == key.publicKey)
        #expect(request.value(forHTTPHeaderField: "X-Member") == nil)
        #expect(try isSigned(request, by: key))
    }

    @Test func `should read the member this device joined once its code is approved`() async throws {
        let body = #"{"username":"tokenwhale","visible":true,"standing":null,"days":[],"devices":[]}"#

        let approval = try await client(body: body).approval(of: key)

        guard case .approved(let summary) = approval else { Issue.record("not approved: \(approval)"); return }
        #expect(summary.username == "tokenwhale")
    }

    @Test func `should say the code expired when the server no longer knows the waiting key`() async {
        await #expect(throws: LeaderboardError.codeExpired) {
            _ = try await client(status: 401, body: #"{"error":"unauthorized","message":"expired"}"#).approval(of: key)
        }
    }

    @Test func `should read what approving a code would add, signed, before approving it`() async throws {
        var sent: URLRequest?
        let code = try #require(DeviceCode("WDJB-MJHT"))

        let pending = try await client(body: #"{"label":"Mac mini","requestedAt":"2026-10-04T09:30:00Z"}"#, sent: { sent = $0 })
            .pendingDevice(code: code, as: member)

        let request = try #require(sent)
        #expect(request.url?.path == "/me/devices/pending/WDJBMJHT")
        #expect(request.httpMethod == "GET")
        #expect(try isSigned(request, by: key))
        #expect(pending == PendingDevice(label: "Mac mini", requestedAt: Date(timeIntervalSince1970: 1_791_106_200)))
    }

    @Test func `should approve a code, signed, and read the device it added`() async throws {
        var sent: URLRequest?
        let code = try #require(DeviceCode("WDJB-MJHT"))
        let body = #"{"publicKey":"newkey","label":"Mac mini","addedAt":"2026-10-04T09:31:00Z"}"#

        let device = try await client(status: 201, body: body, sent: { sent = $0 }).approveDevice(code: code, as: member)

        let request = try #require(sent)
        let sentBody = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(request.url?.path == "/me/devices")
        #expect(request.httpMethod == "POST")
        #expect(sentBody == ["code": "WDJBMJHT"])
        #expect(try isSigned(request, by: key))
        #expect(device == Device(publicKey: "newkey", label: "Mac mini", addedAt: Date(timeIntervalSince1970: 1_791_106_260)))
    }

    @Test func `should remove a device by its key, signed`() async throws {
        var sent: URLRequest?
        try await client(sent: { sent = $0 }).removeDevice("k-2_x", as: member)

        #expect(sent?.url?.path == "/me/devices/k-2_x")
        #expect(sent?.httpMethod == "DELETE")
        #expect(try isSigned(#require(sent), by: key))
    }

    @Test func `should delete a removed device's days, all of them or one provider's on one day`() async throws {
        var sent: [URLRequest] = []
        let client = client(sent: { sent.append($0) })

        try await client.deleteDays(of: "k2", provider: nil, day: nil, as: member)
        try await client.deleteDays(of: "k2", provider: "claude", day: "2026-10-06", as: member)

        #expect(sent.map(\.httpMethod) == ["DELETE", "DELETE"])
        #expect(sent[0].url?.path == "/me/devices/k2/days" && sent[0].url?.query == nil)
        #expect(sent[1].url?.query == "provider=claude&day=2026-10-06")
        #expect(try sent.allSatisfy { try isSigned($0, by: key) })
    }

    @Test func `should encode a provider that holds query characters, and sign the query as sent`() async throws {
        var sent: [URLRequest] = []
        let client = client(body: #"{"standings":[]}"#, sent: { sent.append($0) })

        try await client.deleteDays(of: "k2", provider: "a&day=x#y", day: nil, as: member)
        _ = try await client.board(period: .today, provider: "a&b")

        #expect(sent[0].url?.query == "provider=a%26day%3Dx%23y")
        #expect(try isSigned(sent[0], by: key))
        #expect(sent[1].url?.query == "period=today&provider=a%26b")
    }

    @Test func `should read the member's devices on /me`() async throws {
        let body = #"{"username":"tokenwhale","visible":true,"standing":null,"days":[],"devices":[{"publicKey":"k1","label":"MacBook Pro","addedAt":"2026-10-01T08:00:00Z","removedAt":null,"removedBy":null}]}"#

        let summary = try await client(body: body).me(period: .sevenDays, provider: nil, as: member)

        #expect(summary.devices == [Device(publicKey: "k1", label: "MacBook Pro", addedAt: Date(timeIntervalSince1970: 1_790_841_600))])
    }

    @Test(arguments: [
        (404, #"{"error":"unknownCode","message":"No such code."}"#, LeaderboardError.unknownCode),
        (409, #"{"error":"deviceLimit","message":"Five devices."}"#, LeaderboardError.deviceLimit),
        (403, #"{"error":"deviceTooNew","message":"Too new."}"#, LeaderboardError.deviceTooNew),
        (409, #"{"error":"lastDevice","message":"Last one."}"#, LeaderboardError.lastDevice),
    ])
    func `should tell each device refusal apart`(status: Int, body: String, error: LeaderboardError) async throws {
        let code = try #require(DeviceCode("WDJB-MJHT"))
        await #expect(throws: error) { _ = try await client(status: status, body: body).approveDevice(code: code, as: member) }
    }

    @Test func `should say which device removed this one when the server refuses its key`() async {
        let body = #"{"error":"unauthorized","message":"This device was removed.","removedBy":{"publicKey":"k1","label":"MacBook Pro"}}"#

        await #expect(throws: LeaderboardError.removed(by: "MacBook Pro")) {
            _ = try await client(status: 401, body: body).upload([], as: member)
        }
    }

    // MARK: - Failures

    @Test func `should say the key no longer matches when the server refuses the signature`() async {
        await #expect(throws: LeaderboardError.unauthorized) {
            try await client(status: 401, body: #"{"error":"unauthorized","message":"no"}"#).leave(as: member)
        }
    }

    @Test func `should show the server's own words when it explains a refusal`() async {
        await #expect(throws: LeaderboardError.rejected("This Mac's clock is more than five minutes off.")) {
            try await client(status: 401, body: #"{"error":"clock","message":"This Mac's clock is more than five minutes off."}"#)
                .leave(as: member)
        }
        await #expect(throws: LeaderboardError.rejected("a day can't be in the future")) {
            _ = try await client(status: 400, body: #"{"error":"badDay","message":"a day can't be in the future"}"#).upload([], as: member)
        }
    }

    @Test func `should say the leaderboard is unreachable when the server fails or there is no connection`() async {
        await #expect(throws: LeaderboardError.unreachable) {
            try await client(status: 503, body: "oops").board(period: .today, provider: nil)
        }
        await #expect(throws: LeaderboardError.unreachable) {
            try await failing(URLError(.notConnectedToInternet)).board(period: .today, provider: nil)
        }
    }
}
