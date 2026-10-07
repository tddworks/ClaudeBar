import ClaudeBarKit
import Foundation

// The face of the leaderboard's values: Swift names for their companions, and Dates.

extension ProfileLink {
    /// What the person typed, read as a handle on `platform`; nil when it isn't one.
    public static func typed(_ text: String, on platform: ProfileLink.Platform) -> ProfileLink? {
        companion.typed(text: text, platform: platform)
    }
}

extension Username {
    /// A name the board accepts, or nil.
    public static func named(_ text: String) -> Username? {
        companion.of(text: text)
    }
}

extension RankCard {
    public static func of(standing: Standing?, in view: BoardView, board: [Standing]) -> RankCard? {
        companion.of(standing: standing, view: view, board: board)
    }
}

extension LeaderboardMembership {
    /// When the last good upload was; nil before the first.
    public var lastUpload: Date? { lastUploadSeconds.map { Date(kernelSeconds: $0.doubleValue) } }
}

extension DailyTokens {
    /// A day as the member's own date names it, `yyyy-MM-dd`.
    public static func day(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension BoardView {
    /// A period across every provider.
    public convenience init(period: BoardPeriod) {
        self.init(period: period, provider: nil)
    }
}

extension BoardView: @retroactive @unchecked Sendable {}
extension MemberSummary: @retroactive @unchecked Sendable {}
extension GlobeSummary: @retroactive @unchecked Sendable {}

extension Standing: @retroactive Identifiable {}

extension Standing {
    /// A standing as a board lists it; the token split and the link left out.
    public convenience init(rank: Int, username: String, total: Int64, byProvider: [String: Int64] = [:]) {
        self.init(rank: Int32(rank), username: username, total: total, input: 0, output: 0, cache: 0,
                  byProvider: byProvider.mapValues { KotlinLong(value: $0) }, link: nil)
    }
}
