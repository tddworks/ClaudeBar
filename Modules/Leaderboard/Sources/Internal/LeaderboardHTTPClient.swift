import DataSources
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The leaderboard server (`claudebar-api.tddworks.com`) over HTTPS. Signed calls are
/// signed over the exact bytes sent; the host is fixed, so a setting can't
/// point the app's key at someone else's server.
struct LeaderboardHTTPClient: LeaderboardAPI {
    static let defaultHost = URL(string: "https://claudebar-api.tddworks.com")!

    private let networkClient: any NetworkClient
    private let host: URL
    /// How the app names itself on every request (`X-Client`), so the server
    /// can tell clients apart and refuse one broken version alone.
    private let client: String
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date

    init(networkClient: any NetworkClient = URLSession.shared, host: URL = LeaderboardHTTPClient.defaultHost,
         client: String, timeout: TimeInterval = 15, now: @escaping @Sendable () -> Date = Date.init) {
        self.networkClient = networkClient
        self.host = host
        self.client = client
        self.timeout = timeout
        self.now = now
    }

    // MARK: - LeaderboardAPI

    func join(username: String, publicKey: String, label: String) async throws {
        _ = try await send("POST", "/join", body: try JSONEncoder().encode(["username": username, "publicKey": publicKey, "label": label]))
    }

    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws -> [RefusedDay] {
        let body = try JSONEncoder().encode(Upload(today: DailyTokens.day(of: now()), days: days))
        let answer = try await send("PUT", "/usage", body: body, signedBy: Signer(credentials))
        // A server from before devices answers with no body, or with an object that has
        // no `refused`: it refused nothing alone. Any other answer that can't be read -
        // cut short, not an object, a `refused` of the wrong shape - fails the upload, so
        // the days waiting to be sent again aren't dropped as if taken.
        if answer.isEmpty { return [] }
        return (try decode(UploadAnswer.self, answer).refused ?? []).compactMap { row in
            // A row the server couldn't read as an object names no provider or day; ours
            // are always objects, and such a row can't be sent again anyway.
            guard let provider = row.provider, let day = row.day else { return nil }
            return RefusedDay(provider: provider, day: day, reason: row.reason)
        }
    }

    func me(period: BoardPeriod, provider: String?, as credentials: MemberCredentials) async throws -> MemberSummary {
        let data = try await send("GET", "/me", query: Self.query(period, provider), signedBy: Signer(credentials))
        return try decode(MemberSummary.self, data)
    }

    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws {
        _ = try await send("PATCH", "/me", body: try JSONEncoder().encode(change), signedBy: Signer(credentials))
    }

    func leave(as credentials: MemberCredentials) async throws {
        _ = try await send("DELETE", "/me", signedBy: Signer(credentials))
    }

    func board(period: BoardPeriod, provider: String?) async throws -> [Board.Member] {
        try decode(BoardAnswer.self, try await send("GET", "/board", query: Self.query(period, provider))).standings
    }

    func globe(period: BoardPeriod) async throws -> GlobeSummary {
        try decode(GlobeSummary.self, try await send("GET", "/globe", query: Self.query(period, nil)))
    }

    // MARK: - Devices

    func requestDevice(publicKey: String, label: String) async throws -> DeviceAuthorization {
        let data = try await send("POST", "/devices", body: try JSONEncoder().encode(["publicKey": publicKey, "label": label]))
        let answer = try decode(AuthorizationAnswer.self, data)
        guard let code = DeviceCode(answer.code) else {
            throw LeaderboardError.rejected("The leaderboard answered with something unreadable.")
        }
        return DeviceAuthorization(code: code, expiresIn: answer.expiresIn, interval: answer.interval)
    }

    func approval(of key: SigningKey) async throws -> DeviceApproval {
        do {
            let (data, status) = try await exchange("GET", "/me", query: Self.query(.today, nil), signedBy: Signer(member: nil, key: key))
            return status == 202 ? .waiting : .approved(try decode(MemberSummary.self, data))
        } catch LeaderboardError.unauthorized {
            throw LeaderboardError.codeExpired
        }
    }

    func pendingDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> PendingDevice {
        try decode(PendingDevice.self, try await send("GET", "/me/devices/pending/\(code.value)", signedBy: Signer(credentials)))
    }

    func approveDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> Device {
        let body = try JSONEncoder().encode(["code": code.value])
        return try decode(Device.self, try await send("POST", "/me/devices", body: body, signedBy: Signer(credentials)))
    }

    func removeDevice(_ publicKey: String, as credentials: MemberCredentials) async throws {
        _ = try await send("DELETE", "/me/devices/\(publicKey)", signedBy: Signer(credentials))
    }

    func deleteDays(of publicKey: String, provider: String?, day: String?, as credentials: MemberCredentials) async throws {
        _ = try await send("DELETE", "/me/devices/\(publicKey)/days", query: Self.query([("provider", provider), ("day", day)]),
                           signedBy: Signer(credentials))
    }

    // MARK: - Wire

    private struct Upload: Encodable {
        let today: String
        let days: [DailyTokens]
    }

    private struct UploadAnswer: Decodable {
        struct Refused: Decodable {
            let provider: String?
            let day: String?
            let reason: String
        }

        /// `nil` only when the key is missing: a server from before devices. A `refused`
        /// that is there must be a list - `null` included fails - or the days waiting to be
        /// sent again would be dropped as if taken.
        let refused: [Refused]?

        private enum CodingKeys: String, CodingKey { case refused }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.refused) {
                refused = try container.decode([Refused].self, forKey: .refused)
            } else {
                refused = nil
            }
        }
    }

    private struct BoardAnswer: Decodable {
        let standings: [Board.Member]
    }

    private struct AuthorizationAnswer: Decodable {
        let code: String
        let expiresIn: TimeInterval
        let interval: TimeInterval
    }

    private struct Failure: Decodable {
        let error: String
        let message: String
        /// On a removed device's key: the device that removed it.
        let removedBy: DeviceRef?
    }

    /// Who signs: a member's device, or a new device still waiting for
    /// approval, which names no member.
    private struct Signer {
        let member: Username?
        let key: SigningKey

        init(member: Username?, key: SigningKey) {
            self.member = member
            self.key = key
        }

        init(_ credentials: MemberCredentials) {
            self.init(member: credentials.username, key: credentials.key)
        }
    }

    private static func query(_ period: BoardPeriod, _ provider: String?) -> String? {
        query([("period", period.rawValue), ("provider", provider)])
    }

    /// `name=value` pairs, the values percent-encoded, leaving out those without
    /// a value; `nil` when none has one. The signer signs this exact string,
    /// so a value can't change the query the server reads.
    private static func query(_ pairs: [(String, String?)]) -> String? {
        let parts = pairs.compactMap { name, value in value.map { "\(name)=\(encoded($0))" } }
        return parts.isEmpty ? nil : parts.joined(separator: "&")
    }

    /// RFC 3986's unreserved characters stay; every other byte is escaped, the
    /// same on every platform's Foundation.
    private static func encoded(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private func send(_ method: String, _ path: String, query: String? = nil, body: Data? = nil,
                      signedBy signer: Signer? = nil) async throws -> Data {
        try await exchange(method, path, query: query, body: body, signedBy: signer).data
    }

    /// A request and its answer's body and status, for a call that tells `200` from `202`.
    private func exchange(_ method: String, _ path: String, query: String? = nil, body: Data? = nil,
                          signedBy signer: Signer? = nil) async throws -> (data: Data, status: Int) {
        let pathAndQuery = path + (query.map { "?" + $0 } ?? "")
        guard let url = URL(string: pathAndQuery, relativeTo: host) else { throw LeaderboardError.unreachable }
        // The board is cacheable for the web page; the app always reads it fresh,
        // or a board fetched before your first upload would hide you for minutes.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(client, forHTTPHeaderField: "X-Client")
        if let signer {
            let headers = try RequestSigner.headers(
                member: signer.member, key: signer.key, method: method, pathAndQuery: pathAndQuery,
                body: body ?? Data(), timestamp: Int(now().timeIntervalSince1970), nonce: RequestSigner.makeNonce())
            for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            throw LeaderboardError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return (data, status) }
        throw Self.error(status: status, data: data)
    }

    private static func error(status: Int, data: Data) -> LeaderboardError {
        let failure = try? JSONDecoder().decode(Failure.self, from: data)
        switch (status, failure?.error) {
        case (401, "unauthorized"), (401, nil): return failure?.removedBy.map { .removed(by: $0.label) } ?? .unauthorized
        case (409, "usernameTaken"), (409, nil): return .usernameTaken
        case (409, "deviceLimit"): return .deviceLimit
        case (409, "lastDevice"): return .lastDevice
        case (403, "deviceTooNew"): return .deviceTooNew
        case (404, "unknownCode"): return .unknownCode
        case (400..<500, _): return .rejected(failure?.message ?? "The leaderboard refused that (\(status)).")
        default: return .unreachable
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LeaderboardError.rejected("The leaderboard answered with something unreadable.")
        }
    }
}
