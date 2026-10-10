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

    var summary = MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: true)
    var authorization = DeviceAuthorization(code: DeviceCode("WDJBMJHT")!, expiresIn: 600, interval: 0)
    /// `GET /me` from a waiting key, answered in turn; the last answer repeats.
    var approvals: [Result<DeviceApproval, LeaderboardError>] = []
    var pending = PendingDevice(label: "Mac mini", requestedAt: Date(timeIntervalSince1970: 1_791_106_200))
    var approved = Device(publicKey: "newkey", label: "Mac mini", addedAt: Date(timeIntervalSince1970: 1_791_106_260))
    var removeFailure: LeaderboardError?
    var deleteDaysFailure: LeaderboardError?

    private(set) var joinedLabel: String?
    private(set) var requested: (publicKey: String, label: String)?
    private(set) var approvalsAsked = 0
    private(set) var approvedCode: DeviceCode?
    private(set) var removed: [String] = []
    private(set) var deletedDays: [DeletedDays] = []

    func join(username: String, publicKey: String, label: String) async throws {
        joinedLabel = label
    }

    func requestDevice(publicKey: String, label: String) async throws -> DeviceAuthorization {
        requested = (publicKey, label)
        return authorization
    }

    func approval(of key: SigningKey) async throws -> DeviceApproval {
        let answer = approvals[min(approvalsAsked, approvals.count - 1)]
        approvalsAsked += 1
        return try answer.get()
    }

    func pendingDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> PendingDevice {
        pending
    }

    func approveDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> Device {
        approvedCode = code
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

    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws -> [RefusedDay] { [] }
    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws {}
    func leave(as credentials: MemberCredentials) async throws {}
    func board(period: BoardPeriod, provider: String?) async throws -> [Board.Member] { [] }
    func globe(period: BoardPeriod) async throws -> GlobeSummary { GlobeSummary(countries: [], present: []) }
}

extension MockMachineIdentity {
    /// A machine whose model reads as `model`.
    static func named(_ model: String) -> MockMachineIdentity {
        let machine = MockMachineIdentity()
        given(machine).model.willReturn(DeviceLabel(model)!)
        return machine
    }
}
