import Foundation
import Testing
@testable import Leaderboard

/// A new Mac asking to be added to a member (design §2a): it waits at the
/// server's pace, names the member once approved, and keeps nothing until the
/// person agrees; it expires, or removes itself when they don't know the member.
@MainActor
@Suite
struct DeviceRequestTests {
    private let server = DeviceServer()
    /// Each wait the request took between asking whether it was approved.
    private let waits = Waits()

    private func request(interval: TimeInterval = 5) -> DeviceRequest {
        let waits = waits
        return DeviceRequest(code: server.authorization.code, key: SigningKey.generate(), interval: interval, api: server,
                             sleep: { waits.taken.append($0) })
    }

    // MARK: - Waiting

    @Test func `should wait the interval the server gave before asking again whether it was approved`() async throws {
        server.approvals = [.success(.waiting), .success(.waiting), .success(.approved(server.summary))]
        let request = request(interval: 5)

        _ = try await request.waitForApproval()

        #expect(waits.taken == [5, 5])
        #expect(server.approvalsAsked == 3)
    }

    @Test func `should name the member it was added to once approved`() async throws {
        server.approvals = [.success(.approved(server.summary))]
        let request = request()

        let member = try await request.waitForApproval()

        #expect(member.value == "tokenwhale")
        #expect(request.stage == .approved(member: member))
    }

    /// A view's `.task` can ask again while the first wait still runs (#540):
    /// one wait, at the server's pace, and both hear the same member.
    @Test func `should ask at the server's pace once, however many wait at the same time`() async throws {
        server.approvals = [.success(.waiting), .success(.waiting), .success(.approved(server.summary))]
        let request = request(interval: 5)

        async let first = request.waitForApproval()
        async let second = request.waitForApproval()
        let members = try await [first, second]

        #expect(members.map(\.value) == ["tokenwhale", "tokenwhale"])
        #expect(server.approvalsAsked == 3)
        #expect(waits.taken == [5, 5])
    }

    @Test func `should answer the member again once approved, without asking the server again`() async throws {
        server.approvals = [.success(.approved(server.summary))]
        let request = request()
        let member = try await request.waitForApproval()

        let again = try await request.waitForApproval()

        #expect(again == member)
        #expect(server.approvalsAsked == 1)
    }

    @Test func `should end as expired when the code expires before anyone approves it`() async throws {
        server.approvals = [.success(.waiting), .failure(.codeExpired)]
        let request = request()

        await #expect(throws: LeaderboardError.codeExpired) { _ = try await request.waitForApproval() }

        #expect(request.stage == .expired)
    }

    // MARK: - The person's answer

    @Test func `should remove itself from the member when the person doesn't know them`() async throws {
        server.approvals = [.success(.approved(server.summary))]
        let request = request()
        _ = try await request.waitForApproval()

        try await request.decline()

        #expect(server.removed == [request.key.publicKey])
        #expect(request.stage == .declined)
    }

    @Test func `should hand over the member and its key once, when approved`() async throws {
        server.approvals = [.success(.approved(server.summary))]
        let request = request()
        let member = try await request.waitForApproval()

        let approval = try request.handOver()

        #expect(approval.member == member)
        #expect(approval.key.publicKey == request.key.publicKey)
        #expect(approval.summary == server.summary)
        #expect(request.stage == .joined)
        #expect(throws: LeaderboardError.notJoined) { try request.handOver() }
    }

    @Test func `should hand nothing over while it still waits`() {
        let request = request()

        #expect(throws: LeaderboardError.notJoined) { try request.handOver() }

        #expect(request.stage == .waiting)
    }
}

/// The waits a request took, in order.
@MainActor
final class Waits {
    var taken: [TimeInterval] = []
}
