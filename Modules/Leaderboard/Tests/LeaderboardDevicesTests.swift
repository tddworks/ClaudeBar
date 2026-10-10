import Foundation
import Mockable
import Testing
@testable import Leaderboard

/// Slice 13, adding and removing devices (design §2a, §8): a new device waits
/// for a code to be approved and asks before it uploads; a device past its
/// first week shows each device added since it last looked, once; removing
/// revokes a key, and only another device in its first week offers to delete
/// its days too.
@MainActor
@Suite
struct LeaderboardDevicesTests {
    private let server = DeviceServer()
    private let keys = InMemorySigningKeyStore()
    private let settings = InMemoryLeaderboardSettings()
    private let logs = FakeTokenLogs(providersWithLogs: ["claude", "codex"])
    /// Day 20: devices added on day 13 or before are past their first week.
    private let today = LeaderboardFixtures.date(20)

    private func membership(machine: String = "MacBook Pro") -> LeaderboardMembership {
        let today = today
        return LeaderboardMembership(api: server, keys: keys, settings: settings, logs: logs, machine: MockMachineIdentity.named(machine),
                                     calendar: LeaderboardFixtures.calendar, now: { today })
    }

    private func joined() async throws -> LeaderboardMembership {
        let membership = membership()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        return membership
    }

    /// This device, as `/me` lists it once it reads it.
    private func thisDevice(_ membership: LeaderboardMembership, addedOn day: Int) throws -> Device {
        let key = try SigningKey(rawRepresentation: #require(keys.stored)).publicKey
        return Device(publicKey: key, label: "MacBook Pro", addedAt: LeaderboardFixtures.date(day))
    }

    /// `/me` lists `devices`, and this device reads it.
    private func read(_ devices: [Device], into membership: LeaderboardMembership) async throws {
        server.summary = MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: true, devices: devices)
        _ = try await membership.summary(period: .sevenDays)
    }

    private func device(_ key: String, addedOn day: Int, removedOn removed: Int? = nil) -> Device {
        Device(publicKey: key, label: "Mac \(key)", addedAt: LeaderboardFixtures.date(day),
               removedAt: removed.map { LeaderboardFixtures.date($0) })
    }

    // MARK: - What a device is called

    @Test func `should name this device by the machine's model when it joins`() async throws {
        _ = try await joined()

        #expect(server.joinedLabel == "MacBook Pro")
    }

    @Test func `should name this device as the person typed it when they change the label`() async throws {
        try await membership().join(as: #require(Username("tokenwhale")), sharing: ["claude"], label: #require(DeviceLabel("Work laptop")))

        #expect(server.joinedLabel == "Work laptop")
    }

    // MARK: - A new device: the code, the wait, the question

    @Test func `should show the code the server gave, and stay outside while it waits`() async throws {
        let membership = membership(machine: "Mac mini")

        let code = try await membership.requestToJoin()

        #expect(code == server.authorization.code)
        #expect(server.requested?.label == "Mac mini")
        #expect(membership.joining == .waiting(code: code))
        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
    }

    @Test func `should name the member it joined once approved, and send nothing before the person agrees`() async throws {
        let membership = membership()
        server.approvals = [.success(.waiting), .success(.waiting), .success(.approved(server.summary))]
        _ = try await membership.requestToJoin()

        let member = try await membership.waitForApproval()

        #expect(member.value == "tokenwhale")
        #expect(server.approvalsAsked == 3)
        #expect(membership.joining == .approved(member: member))
        #expect(!membership.isJoined)
        #expect(membership.uploadCredentials == nil)
        #expect(keys.stored == nil && settings.record == nil)
    }

    @Test func `should join as the member it was added to once the person agrees, with nothing uploaded yet`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: false)))]
        _ = try await membership.requestToJoin()
        _ = try await membership.waitForApproval()

        try membership.confirmJoining(sharing: ["codex"])

        #expect(membership.isJoined)
        #expect(membership.joining == nil)
        #expect(membership.username?.value == "tokenwhale")
        #expect(membership.sharing == ["codex"])
        #expect(!membership.isVisible)
        #expect(membership.lastUpload == nil)
        #expect(try SigningKey(rawRepresentation: #require(keys.stored)).publicKey == server.requested?.publicKey)
        #expect(settings.record?.username == "tokenwhale")
    }

    @Test func `should forget the code when it expires before anyone approves it`() async throws {
        let membership = membership()
        server.approvals = [.success(.waiting), .failure(.codeExpired)]
        _ = try await membership.requestToJoin()

        await #expect(throws: LeaderboardError.codeExpired) { _ = try await membership.waitForApproval() }
        #expect(membership.joining == nil)
        #expect(!membership.isJoined)
    }

    @Test func `should remove itself and keep nothing when the person doesn't know the member it was added to`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(server.summary))]
        _ = try await membership.requestToJoin()
        _ = try await membership.waitForApproval()

        try await membership.declineJoining()

        #expect(server.removed == [server.requested?.publicKey])
        #expect(membership.joining == nil)
        #expect(!membership.isJoined)
        #expect(keys.stored == nil && settings.record == nil)
    }

    // MARK: - Approving a new device

    @Test func `should show what a code would add before approving it`() async throws {
        let membership = try await joined()

        let pending = try await membership.pendingDevice(code: #require(DeviceCode("WDJB-MJHT")))

        #expect(pending == server.pending)
    }

    @Test func `should not show a device it approved itself as newly added`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        let code = try #require(DeviceCode("WDJB-MJHT"))

        try await membership.approve(code: code)
        try await read([me, server.approved], into: membership)

        #expect(server.approvedCode == code)
        #expect(membership.addedDevices.isEmpty)
    }

    // MARK: - Seeing a device that was added

    @Test func `should show a device added since this one, once, and not again after a relaunch`() async throws {
        let first = try await joined()
        let me = try thisDevice(first, addedOn: 1)
        let added = device("k2", addedOn: 5)
        try await read([me, added], into: first)

        #expect(first.addedDevices == [added])
        first.markShown(added)
        #expect(first.addedDevices.isEmpty)

        let relaunched = membership()
        try await read([me, added], into: relaunched)
        #expect(relaunched.addedDevices.isEmpty)
    }

    @Test func `should not show the devices the member had before this one, nor one already removed`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 3)

        try await read([device("k1", addedOn: 1), me, device("k2", addedOn: 5, removedOn: 6)], into: membership)

        #expect(membership.addedDevices.isEmpty)
    }

    @Test func `should show a device added during this one's first week once that week ends`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 10)
        // In its first week, `/me` lists this device alone.
        try await read([me], into: membership)
        #expect(membership.addedDevices.isEmpty)

        let added = device("k3", addedOn: 12)
        try await read([device("k1", addedOn: 1), me, added], into: membership)

        #expect(membership.addedDevices == [added])
    }

    @Test func `should show a device added while this one was turned off once it is turned on`() async throws {
        let membership = try await joined()
        let added = device("k2", addedOn: 5)
        membership.turnOff()
        try await read([thisDevice(membership, addedOn: 1), added], into: membership)
        #expect(membership.addedDevices.isEmpty)

        membership.turnOn()

        #expect(membership.addedDevices == [added])
    }

    // MARK: - Removing a device

    @Test func `should offer to delete the days only of another device still in its first week`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        let older = device("k2", addedOn: 5)
        let recent = device("k3", addedOn: 17)
        try await read([me, older, recent], into: membership)

        #expect(membership.offersDeletingDays(whenRemoving: recent))
        #expect(!membership.offersDeletingDays(whenRemoving: older))
        #expect(!membership.offersDeletingDays(whenRemoving: me))
    }

    @Test func `should never count the device that joined as in its first week`() async throws {
        let membership = try await joined()
        let joinedDevice = device("k1", addedOn: 18)
        let me = try thisDevice(membership, addedOn: 19)
        // This device was added a day ago, so it is the one in its first week; the one that joined isn't.
        try await read([joinedDevice, me], into: membership)

        #expect(!membership.offersDeletingDays(whenRemoving: joinedDevice))
    }

    @Test func `should remove another device and keep its days`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        let older = device("k2", addedOn: 5)
        try await read([me, older], into: membership)

        try await membership.remove(device: older, deletingDays: false)

        #expect(server.removed == ["k2"])
        #expect(server.deletedDays.isEmpty)
        #expect(membership.devices.first { $0.publicKey == "k2" }?.removedBy == DeviceRef(publicKey: me.publicKey, label: me.label))
        #expect(membership.isJoined)
    }

    @Test func `should remove a device in its first week and then delete its days`() async throws {
        let membership = try await joined()
        let recent = device("k3", addedOn: 17)
        try await read([thisDevice(membership, addedOn: 1), recent], into: membership)

        try await membership.remove(device: recent, deletingDays: true)

        #expect(server.removed == ["k3"])
        #expect(server.deletedDays == [.init(publicKey: "k3", provider: nil, day: nil)])
    }

    @Test func `should count the device as removed when deleting its days fails, and say why`() async throws {
        let membership = try await joined()
        let recent = device("k3", addedOn: 17)
        try await read([thisDevice(membership, addedOn: 1), recent], into: membership)
        server.deleteDaysFailure = .unreachable

        await #expect(throws: LeaderboardError.unreachable) { try await membership.remove(device: recent, deletingDays: true) }

        #expect(server.removed == ["k3"])
        #expect(membership.devices.first { $0.publicKey == "k3" }?.isRemoved == true)
    }

    @Test func `should forget this device's key only once the server removed it`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        try await read([me, device("k2", addedOn: 5)], into: membership)

        try await membership.remove(device: me)

        #expect(server.removed == [me.publicKey])
        #expect(!membership.isJoined)
        #expect(keys.stored == nil && settings.record == nil)
    }

    @Test func `should keep this device joined when the server doesn't remove it`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        try await read([me], into: membership)
        server.removeFailure = .lastDevice

        await #expect(throws: LeaderboardError.lastDevice) { try await membership.remove(device: me) }

        #expect(membership.isJoined)
        #expect(keys.stored != nil)
    }

    @Test func `should delete a removed device's days for one provider on one day`() async throws {
        let membership = try await joined()
        let removed = device("k2", addedOn: 5, removedOn: 9)
        try await read([thisDevice(membership, addedOn: 1), removed], into: membership)

        try await membership.deleteDays(of: removed, provider: "claude", day: "2026-10-06")

        #expect(server.deletedDays == [.init(publicKey: "k2", provider: "claude", day: "2026-10-06")])
    }
}
