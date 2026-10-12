import Foundation
import Mockable
@testable import Leaderboard

/// A leaderboard server for the device tests: it answers as told, and keeps
/// what each device call asked of it, so a test reads the outcome.
final class DeviceServer: LeaderboardAPI, @unchecked Sendable {
    struct DeletedDays: Equatable {
        let publicKey: String
        let provider: String?
        let day: String?
    }

    struct Upload: Equatable {
        /// The public half of the key it was signed with.
        let key: String
        let days: [DailyTokens]
    }

    var summary = MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: true)
    var authorization = DeviceAuthorization(code: DeviceCode("WDJBMJHT")!, expiresIn: 600, interval: 0)
    /// `GET /me` from a waiting key, answered in turn; the last answer repeats.
    var approvals: [Result<DeviceApproval, LeaderboardError>] = []
    var pending = PendingDevice(label: DeviceLabel("Mac mini")!, requestedAt: Date(timeIntervalSince1970: 1_791_106_200))
    var approved = Device(publicKey: DeviceKey("newkey"), label: DeviceLabel("Mac mini")!, addedAt: Date(timeIntervalSince1970: 1_791_106_260))
    var removeFailure: LeaderboardError?
    var deleteDaysFailure: LeaderboardError?
    var requestFailure: LeaderboardError?
    var approveFailure: LeaderboardError?
    /// When set, the first `join` waits until `releaseJoin()`, as a slow
    /// server does; a join after it fails with `laterJoinFailure`, if set.
    var holdsFirstJoin = false
    var laterJoinFailure: LeaderboardError?
    /// When set, `requestDevice`, or `approval(of:)`, waits until `release()`,
    /// as a slow server does, so a test can act while a call is in flight.
    var holdsRequests = false
    var holdsApprovals = false

    private(set) var joinedLabel: String?
    private(set) var joinedKey: String?
    private(set) var isHoldingJoin = false
    private(set) var requested: (publicKey: String, label: String)?
    private(set) var requests = 0
    private(set) var approvalsAsked = 0
    private(set) var approvedCode: DeviceCode?
    /// The public half of the key that approved the last code.
    private(set) var approvedBy: String?
    private(set) var removed: [String] = []
    private(set) var uploads: [Upload] = []
    private(set) var deletedDays: [DeletedDays] = []
    private var joins = 0
    private var heldJoin: CheckedContinuation<Void, Never>?
    private var held: [CheckedContinuation<Void, Never>] = []
    private(set) var isHolding = false
    /// How many calls the server is holding.
    var heldCalls: Int { held.count }

    /// Waits while `holds`, until `release()`.
    private func hold(while holds: Bool) async {
        guard holds else { return }
        await withCheckedContinuation { continuation in
            held.append(continuation)
            isHolding = true
        }
    }

    func release() {
        isHolding = false
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func join(username: String, publicKey: String, label: String) async throws {
        joins += 1
        if joins > 1, let laterJoinFailure { throw laterJoinFailure }
        joinedLabel = label
        joinedKey = publicKey
        guard holdsFirstJoin, joins == 1 else { return }
        await withCheckedContinuation { continuation in
            heldJoin = continuation
            isHoldingJoin = true
        }
    }

    func releaseJoin() {
        isHoldingJoin = false
        heldJoin?.resume()
        heldJoin = nil
    }

    func requestDevice(publicKey: String, label: String) async throws -> DeviceAuthorization {
        if let requestFailure { throw requestFailure }
        await hold(while: holdsRequests)
        requests += 1
        requested = (publicKey, label)
        return authorization
    }

    func approval(of key: SigningKey) async throws -> DeviceApproval {
        await hold(while: holdsApprovals)
        let answer = approvals[min(approvalsAsked, approvals.count - 1)]
        approvalsAsked += 1
        return try answer.get()
    }

    func pendingDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> PendingDevice {
        pending
    }

    func approveDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> Device {
        if let approveFailure { throw approveFailure }
        approvedCode = code
        approvedBy = credentials.key.publicKey
        return approved
    }

    func removeDevice(_ publicKey: String, as credentials: MemberCredentials) async throws {
        if let removeFailure { throw removeFailure }
        removed.append(publicKey)
    }

    func deleteDays(of publicKey: String, provider: String?, day: String?, as credentials: MemberCredentials) async throws {
        if let deleteDaysFailure { throw deleteDaysFailure }
        deletedDays.append(DeletedDays(publicKey: publicKey, provider: provider, day: day))
    }

    func me(period: BoardPeriod, provider: String?, as credentials: MemberCredentials) async throws -> MemberSummary {
        summary
    }

    func export(as credentials: MemberCredentials) async throws -> Data { Data() }
    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws -> [RefusedDay] {
        uploads.append(Upload(key: credentials.key.publicKey, days: days))
        return []
    }
    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws {}
    func leave(as credentials: MemberCredentials) async throws {}
    func board(period: BoardPeriod, provider: String?) async throws -> [Board.Member] { [] }
    func globe(period: BoardPeriod) async throws -> GlobeSummary { GlobeSummary(countries: [], present: []) }
}

extension MockMachineIdentity {
    /// A machine whose model reads as `model`, and whose hardware UUID is
    /// `uuid`; `nil` is a machine whose UUID can't be read.
    static func named(_ model: String, uuid: String? = "8C3A1F2E-5B7D-4C9E-A1B2-0F3E4D5C6B7A") -> MockMachineIdentity {
        let machine = MockMachineIdentity()
        given(machine).model.willReturn(DeviceLabel(model)!)
        given(machine).hardwareUUID.willReturn(uuid)
        return machine
    }
}
