import Foundation
import Observation

/// *DEVICE REQUEST* (design §2a): this Mac asking to be added to a member,
/// with the code it shows until a Mac the member has approves it. A Mac is
/// either asking or a member's device, never both, so the request is its own
/// aggregate, as `device_requests` is on the server. Its key lives only here,
/// never saved, until the person agrees to the member it was added to and
/// `LeaderboardMembership.join(through:sharing:)` takes it.
@MainActor
@Observable
public final class DeviceRequest {
    /// Where the request stands.
    public enum Stage: Sendable, Equatable {
        /// It shows `code` until a device of the member approves it.
        case waiting
        /// A device of `member` approved it; nothing is kept or sent until the person agrees.
        case approved(member: Username)
        /// The person agreed: this Mac is that member's device now.
        case joined
        /// The code expired before anyone approved it.
        case expired
        /// The person didn't know the member, and this Mac removed itself.
        case declined
    }

    /// What an approved request hands to the membership it joins: the member,
    /// the key it asked with, and the member's `/me` answer.
    struct Approval {
        let member: Username
        let key: SigningKey
        let summary: MemberSummary
    }

    /// `Stage`, with what an approved request holds: the member's `/me` answer.
    private enum State {
        case waiting
        case approved(member: Username, summary: MemberSummary)
        case joined, expired, declined
    }

    /// The code to type on a Mac the member has.
    public let code: DeviceCode
    /// The key this Mac asked with; saved only once it joins.
    let key: SigningKey
    private var state = State.waiting
    /// The one wait running, shared by whoever waits.
    @ObservationIgnored private var asking: Task<Username, any Error>?

    @ObservationIgnored private let api: any LeaderboardAPI
    @ObservationIgnored private let interval: TimeInterval
    @ObservationIgnored private let sleep: @MainActor (TimeInterval) async throws -> Void

    init(code: DeviceCode, key: SigningKey, interval: TimeInterval, api: any LeaderboardAPI,
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.code = code
        self.key = key
        self.interval = interval
        self.api = api
        self.sleep = sleep
    }

    public var stage: Stage {
        switch state {
        case .waiting: .waiting
        case .approved(let member, _): .approved(member: member)
        case .joined: .joined
        case .expired: .expired
        case .declined: .declined
        }
    }

    /// Asks, at the interval the server gave, until a device of the member
    /// approves the code; answers the member it joined. Nothing is kept or
    /// sent until the person agrees: a code that leaked could have been
    /// approved by someone else. There is one wait at a time: a second caller
    /// (a view's task run again) shares the one running, and once approved
    /// the member is answered without asking again.
    public func waitForApproval() async throws -> Username {
        if case .approved(let member, _) = state { return member }
        if let asking { return try await asking.value }
        guard case .waiting = state else { throw LeaderboardError.notJoined }
        let asking = Task { try await self.askUntilApproved() }
        self.asking = asking
        defer { self.asking = nil }
        return try await asking.value
    }

    private func askUntilApproved() async throws -> Username {
        while true {
            let approval: DeviceApproval
            do {
                approval = try await api.approval(of: key)
            } catch LeaderboardError.codeExpired {
                state = .expired
                throw LeaderboardError.codeExpired
            }
            switch approval {
            case .waiting:
                try await sleep(interval)
            case .approved(let summary):
                guard let member = summary.username.flatMap(Username.init) else {
                    throw LeaderboardError.rejected("The leaderboard answered with something unreadable.")
                }
                state = .approved(member: member, summary: summary)
                return member
            }
        }
    }

    /// The person doesn't know the member this Mac was added to: it removes
    /// itself from that member, and keeps nothing.
    public func decline() async throws {
        guard case .approved(let member, _) = state else { throw LeaderboardError.notJoined }
        try await api.removeDevice(key.publicKey, as: MemberCredentials(username: member, key: key))
        state = .declined
    }

    /// The person agreed, and the membership joins through it: hands over
    /// what joining takes, once, and this Mac is the member's device from
    /// here. Refused until approved, and once handed over.
    func handOver() throws -> Approval {
        guard case .approved(let member, let summary) = state else { throw LeaderboardError.notJoined }
        state = .joined
        return Approval(member: member, key: key, summary: summary)
    }
}
