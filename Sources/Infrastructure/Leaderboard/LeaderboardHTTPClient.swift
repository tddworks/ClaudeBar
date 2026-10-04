import Foundation
import Domain

/// The leaderboard server (`claudebar-api.tddworks.com`) over HTTPS. Signed calls are
/// signed over the exact bytes sent; the host is fixed, so a setting can't
/// point the app's key at someone else's server.
public struct LeaderboardHTTPClient: LeaderboardAPI {
    public static let defaultHost = URL(string: "https://claudebar-api.tddworks.com")!

    private let networkClient: any NetworkClient
    private let host: URL
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date

    public init(networkClient: any NetworkClient = URLSession.shared, host: URL = LeaderboardHTTPClient.defaultHost,
                timeout: TimeInterval = 15, now: @escaping @Sendable () -> Date = Date.init) {
        self.networkClient = networkClient
        self.host = host
        self.timeout = timeout
        self.now = now
    }

    // MARK: - LeaderboardAPI

    public func join(username: String, publicKey: String) async throws {
        _ = try await send("POST", "/join", body: try JSONEncoder().encode(["username": username, "publicKey": publicKey]))
    }

    public func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws {
        let body = try JSONEncoder().encode(Upload(today: DailyTokens.day(of: now()), days: days))
        _ = try await send("PUT", "/usage", body: body, signedBy: credentials)
    }

    public func me(in view: BoardView, as credentials: MemberCredentials) async throws -> MemberSummary {
        let data = try await send("GET", "/me", query: Self.query(view), signedBy: credentials)
        return try decode(MemberSummary.self, data)
    }

    public func update(_ change: MemberChange, as credentials: MemberCredentials) async throws {
        _ = try await send("PATCH", "/me", body: try JSONEncoder().encode(change), signedBy: credentials)
    }

    public func leave(as credentials: MemberCredentials) async throws {
        _ = try await send("DELETE", "/me", signedBy: credentials)
    }

    public func board(in view: BoardView) async throws -> [Standing] {
        try decode(Board.self, try await send("GET", "/board", query: Self.query(view))).standings
    }

    public func globe(in view: BoardView) async throws -> GlobeSummary {
        try decode(GlobeSummary.self, try await send("GET", "/globe", query: Self.query(view)))
    }

    // MARK: - Wire

    private struct Upload: Encodable {
        let today: String
        let days: [DailyTokens]
    }

    private struct Board: Decodable {
        let standings: [Standing]
    }

    private struct Failure: Decodable {
        let error: String
        let message: String
    }

    private static func query(_ view: BoardView) -> String {
        "period=\(view.period.rawValue)" + (view.provider.map { "&provider=\($0)" } ?? "")
    }

    private func send(_ method: String, _ path: String, query: String? = nil, body: Data? = nil,
                      signedBy credentials: MemberCredentials? = nil) async throws -> Data {
        let pathAndQuery = path + (query.map { "?" + $0 } ?? "")
        guard let url = URL(string: pathAndQuery, relativeTo: host) else { throw LeaderboardError.unreachable }
        // The board is cacheable for the web page; the app always reads it fresh,
        // or a board fetched before your first upload would hide you for minutes.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credentials {
            let headers = try RequestSigner.headers(
                member: credentials.username, key: credentials.key, method: method, pathAndQuery: pathAndQuery,
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
        if (200..<300).contains(status) { return data }
        throw Self.error(status: status, data: data)
    }

    private static func error(status: Int, data: Data) -> LeaderboardError {
        let failure = try? JSONDecoder().decode(Failure.self, from: data)
        switch (status, failure?.error) {
        case (409, _): return .usernameTaken
        case (401, "unauthorized"), (401, nil): return .unauthorized
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
