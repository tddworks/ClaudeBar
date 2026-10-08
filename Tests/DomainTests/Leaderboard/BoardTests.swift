import Foundation
import Mockable
import Testing
@testable import Domain

/// A board as this app last read it: what the person saw stays on screen
/// until a newer answer replaces it.
@MainActor
@Suite
struct BoardTests {
    private let api = MockLeaderboardAPI.accepting()
    private let keys = InMemorySigningKeyStore()
    private let settings = InMemoryLeaderboardSettings()
    private let logs = FakeTokenLogs()

    private let whale = Board.Member(rank: 1, username: "whale", total: 900)
    private let me = Board.Member(rank: 2, username: "tokenwhale", total: 500)
    private let minnow = Board.Member(rank: 3, username: "minnow", total: 100)

    private func board(period: BoardPeriod = .sevenDays, provider: String? = nil) async throws -> Board {
        let membership = LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs,
                                               calendar: LeaderboardFixtures.calendar)
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        return Board(period: period, provider: provider, api: api, membership: membership)
    }

    private func serverAnswers(_ members: [Board.Member], you: Board.Member?) {
        given(api).board(period: .any, provider: .any).willReturn(members)
        given(api).me(period: .any, provider: .any, as: .any).willReturn(MemberSummary(onBoard: you, days: [], visible: true))
    }

    @Test func `should say the board was never read before its first read`() async throws {
        let board = try await board()

        #expect(board.members == nil)
        #expect(board.you == nil)
        #expect(board.failure == nil)
    }

    @Test func `should show the board and you on it once read`() async throws {
        let board = try await board()
        serverAnswers([whale, me], you: me)

        await board.read()

        #expect(board.members == [whale, me])
        #expect(board.you == me)
    }

    @Test func `should say no one is on the board, not that it was never read, when the server has no one`() async throws {
        let board = try await board()
        serverAnswers([], you: nil)

        await board.read()

        #expect(board.members == [])
        #expect(board.you == nil)
    }

    @Test func `should replace the last board with the newer one when read again`() async throws {
        let board = try await board()
        serverAnswers([whale, me], you: me)
        await board.read()

        api.reset([.given])
        let overtaken = Board.Member(rank: 3, username: "tokenwhale", total: 500)
        serverAnswers([whale, Board.Member(rank: 2, username: "minnow", total: 600), overtaken], you: overtaken)
        await board.read()

        #expect(board.members?.count == 3)
        #expect(board.you == overtaken)
    }

    @Test func `should keep the last board and say it couldn't update when reading again fails`() async throws {
        let board = try await board()
        serverAnswers([whale, me], you: me)
        await board.read()

        api.reset([.given])
        given(api).board(period: .any, provider: .any).willThrow(LeaderboardError.unreachable)
        given(api).me(period: .any, provider: .any, as: .any).willReturn(MemberSummary(onBoard: me, days: [], visible: true))
        await board.read()

        #expect(board.members == [whale, me])
        #expect(board.you == me)
        #expect(board.failure == .unreachable)
    }

    @Test func `should keep the last board when only you on it fails to come back`() async throws {
        let board = try await board()
        serverAnswers([whale, me], you: me)
        await board.read()

        api.reset([.given])
        given(api).board(period: .any, provider: .any).willReturn([whale, minnow])
        given(api).me(period: .any, provider: .any, as: .any).willThrow(LeaderboardError.unreachable)
        await board.read()

        #expect(board.members == [whale, me])
        #expect(board.you == me)
    }

    @Test func `should clear the failure once a read comes back again`() async throws {
        let board = try await board()
        given(api).board(period: .any, provider: .any).willThrow(LeaderboardError.unreachable)
        given(api).me(period: .any, provider: .any, as: .any).willReturn(MemberSummary(onBoard: me, days: [], visible: true))
        await board.read()

        api.reset([.given])
        serverAnswers([whale, me], you: me)
        await board.read()

        #expect(board.failure == nil)
        #expect(board.members == [whale, me])
    }

    @Test func `should still say it was never read when its first read fails`() async throws {
        let board = try await board()
        given(api).board(period: .any, provider: .any).willThrow(LeaderboardError.unreachable)
        given(api).me(period: .any, provider: .any, as: .any).willReturn(MemberSummary(onBoard: me, days: [], visible: true))

        await board.read()

        #expect(board.members == nil)
        #expect(board.failure == .unreachable)
    }

    @Test func `should ask the server for its own period and provider`() async throws {
        let board = try await board(period: .thirtyDays, provider: "claude")
        given(api).board(period: .value(.thirtyDays), provider: .value("claude")).willReturn([whale])
        given(api).me(period: .value(.thirtyDays), provider: .value("claude"), as: .any)
            .willReturn(MemberSummary(onBoard: nil, days: [], visible: true))

        await board.read()

        #expect(board.members == [whale])
    }
}
