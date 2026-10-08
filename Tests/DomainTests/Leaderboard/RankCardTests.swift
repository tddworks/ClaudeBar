import Testing
@testable import Domain

@Suite
struct RankCardTests {

    private func board(_ count: Int) -> [Board.Member] {
        (1...count).map { Board.Member(rank: $0, username: "member\($0)", total: 1_000 - $0) }
    }

    private func rankCard(rank: Int, on board: [Board.Member], byProvider: [String: Int] = ["claude": 10]) -> RankCard? {
        RankCard(you: Board.Member(rank: rank, username: "itshan", total: 3_820, byProvider: byProvider), period: .sevenDays, provider: nil, board: board)
    }

    @Test func `should say how near the top the member is when they're in the top half`() throws {
        let card = try #require(rankCard(rank: 8, on: board(34)))

        #expect(card.placement == .top(percent: 24))
        #expect(card.members == 34)
    }

    @Test func `should say the rank among every member when they're in the bottom half`() throws {
        let card = try #require(rankCard(rank: 18, on: board(34)))

        #expect(card.placement == .rank(of: 34))
    }

    @Test func `should say top 100 when the board is longer than it lists`() throws {
        let card = try #require(rankCard(rank: 40, on: board(100)))

        #expect(card.placement == .topHundred)
        #expect(card.members == nil)
    }

    @Test func `should claim no place when the member is ranked beyond the board`() throws {
        let card = try #require(rankCard(rank: 140, on: board(100)))

        #expect(card.placement == .none)
    }

    @Test func `should claim no place when the member is ranked but not listed`() throws {
        // A hidden member is ranked for themselves but not on the public board.
        let card = try #require(rankCard(rank: 12, on: board(10)))

        #expect(card.placement == .none)
        #expect(card.members == nil)
    }

    @Test func `should offer nothing to share before the member has a rank`() {
        #expect(RankCard(you: nil, period: .sevenDays, provider: nil, board: board(5)) == nil)
        #expect(RankCard(you: Board.Member(rank: 3, username: "itshan", total: 0), period: .sevenDays, provider: nil, board: board(5)) == nil)
    }

    @Test func `should show the providers by their share, largest first, leaving out the ones with none`() throws {
        let card = try #require(rankCard(rank: 2, on: board(5), byProvider: ["codex": 1, "claude": 3, "mistral": 0]))

        #expect(card.mix == [.init(provider: "claude", percent: 75), .init(provider: "codex", percent: 25)])
    }

    @Test func `should leave out a provider whose share rounds to none`() throws {
        let card = try #require(rankCard(rank: 2, on: board(5), byProvider: ["claude": 996, "codex": 4]))

        #expect(card.mix == [.init(provider: "claude", percent: 100)])
    }

    @Test func `should say which board the rank is on`() throws {
        let card = try #require(RankCard(you: Board.Member(rank: 1, username: "itshan", total: 5), period: .thirtyDays, provider: "codex", board: board(3)))

        #expect(card.period == .thirtyDays)
        #expect(card.provider == "codex")
    }

    @Test func `should size each shape for where it gets posted`() {
        #expect(RankCard.Shape.square.pixels == .init(width: 1080, height: 1080))
        #expect(RankCard.Shape.wide.pixels == .init(width: 1200, height: 630))
    }
}
