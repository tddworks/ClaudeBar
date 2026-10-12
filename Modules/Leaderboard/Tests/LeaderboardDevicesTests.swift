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
        return Device(publicKey: DeviceKey(key), label: DeviceLabel("MacBook Pro")!, addedAt: LeaderboardFixtures.date(day))
    }

    /// `/me` lists `devices`, and this device reads it.
    private func read(_ devices: [Device], into membership: LeaderboardMembership) async throws {
        server.summary = MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: true, devices: devices)
        _ = try await membership.summary(period: .sevenDays)
    }

    private func device(_ key: String, addedOn day: Int, removedOn removed: Int? = nil) -> Device {
        Device(publicKey: DeviceKey(key), label: DeviceLabel("Mac \(key)")!, addedAt: LeaderboardFixtures.date(day),
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

        let request = try await membership.requestToJoin()

        #expect(request.code == server.authorization.code)
        #expect(server.requested?.label == "Mac mini")
        #expect(request.stage == .waiting)
        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
    }

    @Test func `should name the member it joined once approved, and send nothing before the person agrees`() async throws {
        let membership = membership()
        server.approvals = [.success(.waiting), .success(.waiting), .success(.approved(server.summary))]
        let request = try await membership.requestToJoin()

        let member = try await request.waitForApproval()

        #expect(member.value == "tokenwhale")
        #expect(server.approvalsAsked == 3)
        #expect(request.stage == .approved(member: member))
        #expect(!membership.isJoined)
        #expect(membership.uploadCredentials == nil)
        #expect(keys.stored == nil && settings.record == nil)
    }

    @Test func `should join as the member it was added to once the person agrees, with nothing uploaded yet`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(MemberSummary(username: "tokenwhale", onBoard: nil, days: [], visible: false)))]
        let request = try await membership.requestToJoin()
        _ = try await request.waitForApproval()

        try membership.join(through: request, sharing: ["codex"])

        #expect(membership.isJoined)
        #expect(request.stage == .joined)
        #expect(membership.username?.value == "tokenwhale")
        #expect(membership.sharing == ["codex"])
        #expect(!membership.isVisible)
        #expect(membership.lastUpload == nil)
        #expect(try SigningKey(rawRepresentation: #require(keys.stored)).publicKey == server.requested?.publicKey)
        #expect(settings.record?.username == "tokenwhale")
    }

    @Test func `should not join through a request no one has approved yet`() async throws {
        let membership = membership()
        let request = try await membership.requestToJoin()

        #expect(throws: LeaderboardError.notJoined) { try membership.join(through: request, sharing: ["claude"]) }

        #expect(!membership.isJoined)
        #expect(request.stage == .waiting)
    }

    @Test func `should stay approved when what the person picked can't be shared, so they can pick again`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(server.summary))]
        let request = try await membership.requestToJoin()
        let member = try await request.waitForApproval()

        #expect(throws: LeaderboardError.nothingShared) { try membership.join(through: request, sharing: []) }

        #expect(request.stage == .approved(member: member))
        #expect(!membership.isJoined)
    }

    @Test func `should stay approved, keeping no key, when this Mac can't store its key, and join on a second try`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(server.summary))]
        let request = try await membership.requestToJoin()
        let member = try await request.waitForApproval()
        keys.refusesSaving = true

        #expect(throws: LeaderboardError.keyNotKept) { try membership.join(through: request, sharing: ["claude"]) }

        #expect(request.stage == .approved(member: member))
        #expect(!membership.isJoined)
        #expect(keys.stored == nil && settings.record == nil)

        keys.refusesSaving = false
        try membership.join(through: request, sharing: ["claude"])

        #expect(membership.isJoined)
    }

    @Test func `should not join through a request once this Mac is a member, and keep the member's key`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(server.summary))]
        let request = try await membership.requestToJoin()
        _ = try await request.waitForApproval()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        let key = keys.stored
        keys.refusesSaving = true

        #expect(throws: LeaderboardError.alreadyJoined) { try membership.join(through: request, sharing: ["claude"]) }

        #expect(keys.stored == key)
        #expect(membership.isJoined)
    }

    @Test func `should refuse a second join while the first waits for the server, and keep the first one's key`() async throws {
        let membership = membership()
        server.holdsFirstJoin = true
        server.laterJoinFailure = .usernameTaken
        let first = Task { try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"]) }
        while !server.isHoldingJoin { await Task.yield() }

        await #expect(throws: LeaderboardError.alreadyJoined) {
            try await membership.join(as: #require(Username("otherwhale")), sharing: ["claude"])
        }
        server.releaseJoin()
        try await first.value

        #expect(membership.username?.value == "tokenwhale")
        #expect(try SigningKey(rawRepresentation: #require(keys.stored)).publicKey == server.joinedKey)
    }

    @Test func `should not ask to be added to a member while this Mac is already one`() async throws {
        let membership = try await joined()

        await #expect(throws: LeaderboardError.alreadyJoined) { _ = try await membership.requestToJoin() }

        #expect(server.requested == nil)
    }

    @Test func `should remove itself and keep nothing when the person doesn't know the member it was added to`() async throws {
        let membership = membership()
        server.approvals = [.success(.approved(server.summary))]
        let request = try await membership.requestToJoin()
        _ = try await request.waitForApproval()

        try await request.decline()

        #expect(server.removed == [server.requested?.publicKey])
        #expect(request.stage == .declined)
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

    @Test func `should offer deleting its days only when removing another device still in its first week`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        let older = device("k2", addedOn: 5)
        let recent = device("k3", addedOn: 17)
        try await read([me, older, recent], into: membership)

        #expect(membership.removals(of: recent) == [.keepingItsDays, .deletingItsDays])
        #expect(membership.removals(of: older) == [.keepingItsDays])
        #expect(membership.removals(of: me) == [.keepingItsDays])
    }

    @Test func `should never count the device that joined as in its first week`() async throws {
        let membership = try await joined()
        let joinedDevice = device("k1", addedOn: 18)
        let me = try thisDevice(membership, addedOn: 19)
        // This device was added a day ago, so it is the one in its first week; the one that joined isn't.
        try await read([joinedDevice, me], into: membership)

        #expect(membership.removals(of: joinedDevice) == [.keepingItsDays])
    }

    @Test func `should offer nothing for a device already removed`() async throws {
        let membership = try await joined()
        let removed = device("k2", addedOn: 5, removedOn: 9)
        try await read([thisDevice(membership, addedOn: 1), removed], into: membership)

        #expect(membership.removals(of: removed).isEmpty)
    }

    @Test func `should refuse to delete the days of a device it didn't offer that for, and keep it in use`() async throws {
        let membership = try await joined()
        let older = device("k2", addedOn: 5)
        try await read([thisDevice(membership, addedOn: 1), older], into: membership)

        await #expect(throws: LeaderboardError.notOffered) { try await membership.remove(older, .deletingItsDays) }

        #expect(server.removed.isEmpty && server.deletedDays.isEmpty)
        #expect(membership.devices.first { $0.publicKey == DeviceKey("k2") }?.isRemoved == false)
    }

    @Test func `should remove another device and keep its days`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        let older = device("k2", addedOn: 5)
        try await read([me, older], into: membership)

        try await membership.remove(older, .keepingItsDays)

        #expect(server.removed == ["k2"])
        #expect(server.deletedDays.isEmpty)
        #expect(membership.devices.first { $0.publicKey == DeviceKey("k2") }?.removedBy == DeviceRef(publicKey: me.publicKey, label: me.label))
        #expect(membership.isJoined)
    }

    @Test func `should remove a device in its first week and then delete its days`() async throws {
        let membership = try await joined()
        let recent = device("k3", addedOn: 17)
        try await read([thisDevice(membership, addedOn: 1), recent], into: membership)

        try await membership.remove(recent, .deletingItsDays)

        #expect(server.removed == ["k3"])
        #expect(server.deletedDays == [.init(publicKey: "k3", provider: nil, day: nil)])
    }

    @Test func `should count the device as removed when deleting its days fails, and say why`() async throws {
        let membership = try await joined()
        let recent = device("k3", addedOn: 17)
        try await read([thisDevice(membership, addedOn: 1), recent], into: membership)
        server.deleteDaysFailure = .unreachable

        await #expect(throws: LeaderboardError.unreachable) { try await membership.remove(recent, .deletingItsDays) }

        #expect(server.removed == ["k3"])
        #expect(membership.devices.first { $0.publicKey == DeviceKey("k3") }?.isRemoved == true)
    }

    @Test func `should forget this device's key only once the server removed it`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        try await read([me, device("k2", addedOn: 5)], into: membership)

        try await membership.remove(me)

        #expect(server.removed == [me.publicKey.value])
        #expect(!membership.isJoined)
        #expect(keys.stored == nil && settings.record == nil)
    }

    @Test func `should keep this device joined when the server doesn't remove it`() async throws {
        let membership = try await joined()
        let me = try thisDevice(membership, addedOn: 1)
        try await read([me], into: membership)
        server.removeFailure = .lastDevice

        await #expect(throws: LeaderboardError.lastDevice) { try await membership.remove(me) }

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

    // MARK: - A first week, as the Devices list says it

    /// A device added through a code, as it reads itself in its first week:
    /// `/me` lists only it.
    private func added(addedOn day: Int) async throws -> LeaderboardMembership {
        let membership = membership(machine: "Mac mini")
        server.approvals = [.success(.approved(server.summary))]
        let request = try await membership.requestToJoin()
        _ = try await request.waitForApproval()
        try membership.join(through: request, sharing: ["claude"])
        let key = try SigningKey(rawRepresentation: #require(keys.stored)).publicKey
        try await read([Device(publicKey: DeviceKey(key), label: DeviceLabel("Mac mini")!, addedAt: LeaderboardFixtures.date(day))], into: membership)
        return membership
    }

    @Test func `should say when this device's first week ends when it was added, though it sees only itself`() async throws {
        let membership = try await added(addedOn: 16)
        let me = try #require(membership.thisDevice)

        #expect(membership.firstWeekEnds(for: me) == LeaderboardFixtures.date(23))
    }

    @Test func `should never hold the device that joined to a first week, alone on the member or not`() async throws {
        let membership = try await joined()
        try await read([thisDevice(membership, addedOn: 18)], into: membership)

        #expect(membership.firstWeekEnds(for: try #require(membership.thisDevice)) == nil)
    }

    @Test func `should say when another device's first week ends, and nothing once it is over or the device removed`() async throws {
        let membership = try await joined()
        let fresh = device("k2", addedOn: 16)
        let old = device("k3", addedOn: 10)
        let gone = device("k4", addedOn: 17, removedOn: 18)
        try await read([thisDevice(membership, addedOn: 1), fresh, old, gone], into: membership)

        #expect(membership.firstWeekEnds(for: fresh) == LeaderboardFixtures.date(23))
        #expect(membership.firstWeekEnds(for: old) == nil)
        #expect(membership.firstWeekEnds(for: gone) == nil)
    }

    @Test func `should remember across a relaunch that this device was added, and forget it with the membership`() async throws {
        _ = try await added(addedOn: 16)
        #expect(settings.record?.addedAsDevice == true)

        let relaunched = membership(machine: "Mac mini")
        let key = try SigningKey(rawRepresentation: #require(keys.stored)).publicKey
        try await read([Device(publicKey: DeviceKey(key), label: DeviceLabel("Mac mini")!, addedAt: LeaderboardFixtures.date(16))], into: relaunched)
        #expect(relaunched.firstWeekEnds(for: try #require(relaunched.thisDevice)) == LeaderboardFixtures.date(23))

        try await relaunched.remove(try #require(relaunched.thisDevice))
        #expect(settings.record == nil)
    }
}
