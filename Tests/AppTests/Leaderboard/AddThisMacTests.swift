import Domain
import Foundation
import Infrastructure
import Testing
@testable import ClaudeBar

/// *Already a member? Add this Mac* as the popover drives it (design §2a): a
/// code cancelled or asked for again says nothing about its own end, so the
/// person never sees an error for a code they already let go.
@MainActor
@Suite
struct AddThisMacTests {
    private let server = HeldServer()

    private func leaderboard() -> AppLeaderboard {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("add-this-mac-\(UUID().uuidString).json")
        let repository = JSONSettingsRepository(store: JSONSettingsStore(fileURL: file))
        let monitor = QuotaMonitor(providers: Providers([], make: { _ in fatalError("no providers added") }), clock: SystemClock(),
                                   settingsRepository: repository)
        return AppLeaderboard(monitor: monitor, api: server, keys: NoKeys(), machine: Machine(), settings: NoRecord())
    }

    /// Waits, at most two seconds, for the server to hold a call; fails the
    /// test rather than release a hold that never began.
    private func untilHeld(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await until(sourceLocation: sourceLocation) { server.isHolding }
    }

    private func until(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting", sourceLocation: sourceLocation)
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Lets the wait that was released settle, so a stale write would land
    /// before the test reads the state.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func `should show nothing for a code the person cancelled, though its wait ends in an error`() async throws {
        let leaderboard = leaderboard()
        server.holdsApprovals = true
        await leaderboard.requestToJoin()
        try await untilHeld()

        leaderboard.cancelRequest()
        server.release(with: .unreachable)
        try await settle()

        #expect(leaderboard.request == nil)
        #expect(leaderboard.requestFailure == nil)
    }

    @Test func `should show nothing for a replaced code's end, only the new code`() async throws {
        let leaderboard = leaderboard()
        defer { leaderboard.cancelRequest() }
        server.holdsApprovals = true
        await leaderboard.requestToJoin()
        try await untilHeld()
        let first = try #require(leaderboard.request)

        // The new code's wait is held too, and ends with the test.
        await leaderboard.requestToJoin()
        try await until { server.heldCalls == 2 }
        server.releaseFirst(with: .codeExpired)
        try await settle()

        #expect(leaderboard.request != nil && leaderboard.request !== first)
        #expect(leaderboard.requestFailure == nil)
        server.release(with: .codeExpired)
    }

    @Test func `should keep no code that arrives after the person cancelled asking for it`() async throws {
        let leaderboard = leaderboard()
        server.holdsRequests = true
        let asking = Task { await leaderboard.requestToJoin() }
        try await untilHeld()

        leaderboard.cancelRequest()
        server.release(with: nil)
        await asking.value

        #expect(leaderboard.request == nil)
        #expect(!leaderboard.isAskingForCode)
    }

    @Test func `should say why when the code still shown expires`() async throws {
        let leaderboard = leaderboard()
        server.holdsApprovals = true
        await leaderboard.requestToJoin()
        try await untilHeld()

        server.release(with: .codeExpired)
        try await until { leaderboard.requestFailure != nil }

        #expect(leaderboard.requestFailure == .codeExpired)
    }
}

/// A leaderboard server that holds a code request, or each approval ask,
/// until the test releases it with an answer.
private final class HeldServer: LeaderboardAPI, @unchecked Sendable {
    var holdsRequests = false
    var holdsApprovals = false
    private var held: [CheckedContinuation<LeaderboardError?, Never>] = []
    var isHolding: Bool { !held.isEmpty }
    var heldCalls: Int { held.count }

    /// Ends every held call with `failure`, or with an answer when `nil`.
    func release(with failure: LeaderboardError?) {
        let waiting = held
        held = []
        waiting.forEach { $0.resume(returning: failure) }
    }

    /// Ends the call held first, leaving the others held.
    func releaseFirst(with failure: LeaderboardError?) {
        guard !held.isEmpty else { return }
        held.removeFirst().resume(returning: failure)
    }

    private func hold() async -> LeaderboardError? {
        await withCheckedContinuation { held.append($0) }
    }

    func requestDevice(publicKey: String, label: String) async throws -> DeviceAuthorization {
        if holdsRequests, let failure = await hold() { throw failure }
        return DeviceAuthorization(code: DeviceCode("WDJBMJHT")!, expiresIn: 600, interval: 0)
    }

    func approval(of key: SigningKey) async throws -> DeviceApproval {
        if holdsApprovals, let failure = await hold() { throw failure }
        await Task.yield()
        return .waiting
    }

    func me(period: BoardPeriod, provider: String?, as credentials: MemberCredentials) async throws -> MemberSummary {
        MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: true)
    }
    func export(as credentials: MemberCredentials) async throws -> Data { Data() }
    func join(username: String, publicKey: String, label: String) async throws {}
    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws -> [RefusedDay] { [] }
    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws {}
    func leave(as credentials: MemberCredentials) async throws {}
    func board(period: BoardPeriod, provider: String?) async throws -> [Board.Member] { [] }
    func globe(period: BoardPeriod) async throws -> GlobeSummary { throw LeaderboardError.unreachable }
    func pendingDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> PendingDevice { throw LeaderboardError.unknownCode }
    func approveDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> Device { throw LeaderboardError.unknownCode }
    func removeDevice(_ publicKey: String, as credentials: MemberCredentials) async throws {}
    func deleteDays(of publicKey: String, provider: String?, day: String?, as credentials: MemberCredentials) async throws {}
}

private final class NoKeys: SigningKeyStore, @unchecked Sendable {
    func load() -> Data? { nil }
    func save(_ rawKey: Data) {}
    func delete() {}
}

private final class NoRecord: LeaderboardSettingsRepository, @unchecked Sendable {
    func leaderboardRecord() -> LeaderboardRecord? { nil }
    func saveLeaderboardRecord(_ record: LeaderboardRecord?) {}
    func isLeaderboardOn() -> Bool { true }
    func setLeaderboardOn(_ on: Bool) {}
}

private struct Machine: MachineIdentity {
    var model: DeviceLabel { DeviceLabel("Mac mini")! }
    var hardwareUUID: String? { nil }
}
