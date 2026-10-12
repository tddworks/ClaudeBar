import Foundation
import Mockable
import Testing
@testable import Leaderboard
import Quotas

/// Slice 14, a key copied to another Mac (design §2a, §8): beside its key a
/// device keeps a hash of its Mac's hardware UUID, salted with the key's
/// public half. A launch whose Mac isn't the one the hash names holds a copy:
/// it uploads nothing and asks, until the member makes this Mac its own
/// device or keeps the key here.
@MainActor
@Suite
struct LeaderboardCopiedKeyTests {
    private let server = DeviceServer()
    private let keys = InMemorySigningKeyStore()
    private let settings = InMemoryLeaderboardSettings()
    private let logs = FakeTokenLogs(providersWithLogs: ["claude", "codex"])
    private let calendar = LeaderboardFixtures.calendar
    private let today = LeaderboardFixtures.date(20)

    private static let thisMac = "8C3A1F2E-5B7D-4C9E-A1B2-0F3E4D5C6B7A"
    private static let otherMac = "D1E2F3A4-B5C6-4D7E-8F90-A1B2C3D4E5F6"

    /// The app launched on the Mac whose hardware UUID is `uuid`, over the
    /// key store and settings a copy brings along; `nil` is a Mac whose UUID
    /// can't be read.
    private func launch(on uuid: String? = thisMac, keys: InMemorySigningKeyStore? = nil,
                        settings: InMemoryLeaderboardSettings? = nil) -> LeaderboardMembership {
        let today = today
        return LeaderboardMembership(api: server, keys: keys ?? self.keys, settings: settings ?? self.settings, logs: logs,
                                     machine: MockMachineIdentity.named("MacBook Pro", uuid: uuid),
                                     calendar: calendar, now: { today })
    }

    private func joined(on uuid: String? = thisMac) async throws -> LeaderboardMembership {
        let membership = launch(on: uuid)
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        return membership
    }

    /// The membership as a copy of it finds itself on another Mac.
    private func copied() async throws -> LeaderboardMembership {
        _ = try await joined()
        return launch(on: Self.otherMac)
    }

    private func uploader(_ membership: LeaderboardMembership) -> LeaderboardUploader {
        let today = today
        return LeaderboardUploader(membership: membership, logs: logs, api: server, calendar: calendar, now: { today })
    }

    /// Yields until the server holds a call, so the test acts while it is in flight.
    private func heldAtServer() async {
        for _ in 0..<1000 where !server.isHolding { await Task.yield() }
    }

    private var storedKey: String {
        get throws { try SigningKey(rawRepresentation: #require(keys.stored)).publicKey }
    }

    // MARK: - The hash beside the key

    @Test func `should record this Mac beside the key when it joins, so the next launch asks nothing`() async throws {
        _ = try await joined()

        #expect(settings.record?.machine != nil)

        let relaunched = launch()
        #expect(!relaunched.holdsCopiedKey)
        #expect(relaunched.uploadCredentials != nil)
    }

    @Test func `should record this Mac beside the key when it is added as a device too`() async throws {
        let membership = launch()
        server.approvals = [.success(.approved(server.summary))]
        let request = try await membership.requestToJoin()
        _ = try await request.waitForApproval()

        try membership.join(through: request, sharing: ["claude"])

        #expect(settings.record?.machine != nil)
        #expect(!launch().holdsCopiedKey)
    }

    @Test func `should keep a hash, never the UUID, salted with the key so two keys on one Mac don't match`() async throws {
        let otherKeys = InMemorySigningKeyStore()
        let otherSettings = InMemoryLeaderboardSettings()
        _ = try await joined()
        try await launch(keys: otherKeys, settings: otherSettings).join(as: #require(Username("otherwhale")), sharing: ["codex"])

        let first = try #require(settings.record?.machine)
        let second = try #require(otherSettings.record?.machine)
        let key = try storedKey
        #expect(first != second)
        #expect(!first.contains(Self.thisMac) && !first.lowercased().contains(Self.thisMac.lowercased()))
        #expect(first != key)
    }

    @Test func `should give a key from before this rule this Mac's hash, and ask nothing`() async throws {
        _ = try await joined()
        settings.record = settings.record?.with(machine: nil)

        let relaunched = launch()

        #expect(!relaunched.holdsCopiedKey)
        #expect(settings.record?.machine != nil)
        #expect(launch(on: Self.otherMac).holdsCopiedKey, "the hash it recorded is this Mac's")
    }

    @Test func `should keep no hash and ask nothing when this Mac's UUID can't be read`() async throws {
        _ = try await joined(on: nil)
        #expect(settings.record?.machine == nil)
        #expect(!launch(on: nil).holdsCopiedKey)

        let foreign = settings.record?.with(machine: "a hash from some Mac")
        settings.record = foreign
        let relaunched = launch(on: nil)

        #expect(!relaunched.holdsCopiedKey)
        #expect(relaunched.uploadCredentials != nil)
        #expect(settings.record == foreign, "a Mac that can't read its UUID records nothing")
    }

    // MARK: - A copy

    @Test func `should upload nothing and ask when the hash beside the key isn't this Mac's`() async throws {
        let copy = try await copied()
        let before = settings.record
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 20, input: 10)])]

        #expect(copy.holdsCopiedKey)
        #expect(copy.isJoined, "it is still the member's device: it reads, and can answer")
        #expect(copy.uploadCredentials == nil)

        let uploader = uploader(copy)
        await uploader.uploadNow()

        #expect(server.uploads.isEmpty)
        #expect(uploader.lastError == .keyCopied)
        #expect(copy.lastUpload == nil)
        #expect(settings.record == before, "a copy changes nothing until answered")
    }

    @Test func `should keep the key here when told to, recording this Mac and changing nothing else`() async throws {
        let copy = try await copied()
        let before = try #require(settings.record)

        try copy.keepKeyHere()

        #expect(!copy.holdsCopiedKey)
        #expect(copy.uploadCredentials != nil)
        #expect(try storedKey == server.joinedKey)
        #expect(settings.record?.with(machine: nil) == before.with(machine: nil))
        #expect(settings.record?.machine != before.machine)
        #expect(!launch(on: Self.otherMac).holdsCopiedKey)
    }

    @Test func `should become its own device: a new key the copied key approves, the copy forgotten, lastUpload kept`() async throws {
        let member = try await joined()
        member.recordUpload(at: LeaderboardFixtures.date(15), refused: [RefusedDay(provider: "claude", day: "2026-10-14", reason: "later")])
        let copiedKey = try storedKey
        let copiedHash = try #require(settings.record?.machine)
        let copy = launch(on: Self.otherMac)
        server.approvals = [.success(.approved(server.summary))]

        try await copy.becomeOwnDevice()

        #expect(!copy.holdsCopiedKey)
        #expect(copy.ownDeviceRequest == nil)
        let newKey = try storedKey
        #expect(newKey != copiedKey)
        #expect(newKey == server.requested?.publicKey)
        #expect(server.requested?.label == "MacBook Pro")
        #expect(server.approvedCode == server.authorization.code)
        #expect(server.approvedBy == copiedKey, "the copied key, which still signs, approves it")
        #expect(copy.uploadCredentials?.key.publicKey == newKey)
        #expect(copy.lastUpload == LeaderboardFixtures.date(15))
        #expect(copy.refused.isEmpty)
        #expect(copy.username?.value == "tokenwhale")
        #expect(settings.record?.machine != nil && settings.record?.machine != copiedHash)
        #expect(!launch(on: Self.otherMac).holdsCopiedKey)
    }

    @Test func `should send the days from the copied lastUpload on under the new key, not thirty days back`() async throws {
        let member = try await joined()
        member.recordUpload(at: LeaderboardFixtures.date(15))
        let copy = launch(on: Self.otherMac)
        server.approvals = [.success(.approved(server.summary))]
        try await copy.becomeOwnDevice()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 16, input: 10)])]

        await uploader(copy).uploadNow()

        let newKey = try storedKey
        #expect(logs.askedFor == DateRange(first: LeaderboardFixtures.date(15), last: today, calendar: calendar))
        #expect(server.uploads.map(\.key) == [newKey])
        #expect(server.uploads.first?.days.map(\.day) == ["2026-10-16"])
    }

    @Test func `should keep the code for another device to approve when the copied key is in its first week`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.approveFailure = .deviceTooNew

        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }

        #expect(copy.holdsCopiedKey)
        #expect(try storedKey == copiedKey)
        #expect(copy.ownDeviceRequest?.code == server.authorization.code)
        #expect(copy.ownDeviceRequest?.stage == .waiting)

        // A device of the member past its first week approves the code.
        server.approvals = [.success(.approved(server.summary))]
        try await copy.becomeOwnDevice()

        #expect(!copy.holdsCopiedKey)
        #expect(copy.ownDeviceRequest == nil)
        #expect(try storedKey == server.requested?.publicKey)
        #expect(server.requests == 1, "the request it made is the one that was approved")
    }

    /// The code is on screen for another device of the member; a code that
    /// leaked could be approved by someone else's device (design §2a), which
    /// would make this Mac that stranger's device and send its days there.
    @Test func `should refuse a code a stranger's device approved, remove itself from there, and keep the copy`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.approveFailure = .deviceTooNew
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        let stranger = MemberSummary(username: "stranger", onBoard: nil, days: [], visible: true)
        server.approvals = [.success(.approved(stranger))]

        await #expect(throws: LeaderboardError.approvedByStranger) { try await copy.becomeOwnDevice() }

        #expect(copy.holdsCopiedKey)
        #expect(copy.username?.value == "tokenwhale")
        #expect(try storedKey == copiedKey)
        #expect(copy.ownDeviceRequest == nil, "the next try asks for a new code")
        #expect(server.removed == [server.requested?.publicKey], "it removed itself from the stranger's devices")
        #expect(settings.record?.username == "tokenwhale")

        // A new code, which the copied key, still too new, can't approve; a device of the member does.
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        server.approvals = [.success(.approved(server.summary))]
        try await copy.becomeOwnDevice()

        #expect(!copy.holdsCopiedKey)
        #expect(server.requests == 2)
    }

    @Test func `should take an approval under the member's new name when another device renamed them`() async throws {
        let copy = try await copied()
        server.approveFailure = .deviceTooNew
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        let renamed = MemberSummary(username: "tokenWhale2", onBoard: nil, days: [], visible: true)
        server.summary = renamed
        server.approvals = [.success(.approved(renamed))]

        try await copy.becomeOwnDevice()

        #expect(!copy.holdsCopiedKey)
        #expect(copy.username?.value == "tokenWhale2")
        #expect(server.removed.isEmpty)
    }

    @Test func `should ask for a new code once the old one expired before anyone approved it`() async throws {
        let copy = try await copied()
        server.approveFailure = .deviceTooNew
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        server.approvals = [.failure(.codeExpired)]

        await #expect(throws: LeaderboardError.codeExpired) { try await copy.becomeOwnDevice() }

        #expect(copy.holdsCopiedKey)
        #expect(copy.ownDeviceRequest == nil)

        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        #expect(copy.ownDeviceRequest?.code == server.authorization.code, "a new code")
        server.approvals = [.success(.approved(server.summary))]
        try await copy.becomeOwnDevice()

        #expect(!copy.holdsCopiedKey)
        #expect(server.requests == 2)
    }

    // MARK: - One answer at a time

    @Test func `should carry out one switch at a time: a second ask while the first waits for the server adds no device`() async throws {
        let copy = try await copied()
        server.holdsRequests = true
        server.approvals = [.success(.approved(server.summary))]
        let first = Task { try await copy.becomeOwnDevice() }
        await heldAtServer()
        #expect(server.isHolding, "the first ask is at the server")

        let second = Task { try await copy.becomeOwnDevice() }
        for _ in 0..<100 { await Task.yield() }

        #expect(server.heldCalls == 1, "the second ask never reached the server")
        server.holdsRequests = false
        server.release()
        try await first.value
        await #expect(throws: LeaderboardError.notOffered) { try await second.value }

        #expect(!copy.holdsCopiedKey)
        #expect(server.requests == 1, "one device was added, not two")
        #expect(try storedKey == server.requested?.publicKey)
    }

    @Test func `should add nothing when the person chose to keep the key while the switch asked the server for a code`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.holdsRequests = true
        server.approvals = [.success(.approved(server.summary))]
        let switching = Task { try await copy.becomeOwnDevice() }
        await heldAtServer()
        #expect(server.isHolding)

        try copy.keepKeyHere()
        server.holdsRequests = false
        server.release()
        await #expect(throws: LeaderboardError.notOffered) { try await switching.value }

        #expect(!copy.holdsCopiedKey, "the person's answer stands")
        #expect(copy.ownDeviceRequest == nil)
        #expect(try storedKey == copiedKey)
        #expect(server.approvedCode == nil, "the code was never approved, so there is no device to remove")
        #expect(!launch(on: Self.otherMac).holdsCopiedKey, "the hash recorded is the copied key's on this Mac")
    }

    @Test func `should remove the device it added when the person chose to keep the key while the switch waited for its approval`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.holdsApprovals = true
        server.approvals = [.success(.approved(server.summary))]
        let switching = Task { try await copy.becomeOwnDevice() }
        await heldAtServer()
        #expect(server.isHolding, "the copied key approved the code; the switch waits for the server to say so")
        #expect(server.approvedBy == copiedKey)

        try copy.keepKeyHere()
        server.holdsApprovals = false
        server.release()
        await #expect(throws: LeaderboardError.notOffered) { try await switching.value }

        #expect(!copy.holdsCopiedKey, "the person's answer stands")
        #expect(copy.ownDeviceRequest == nil)
        #expect(try storedKey == copiedKey)
        #expect(copy.uploadCredentials?.key.publicKey == copiedKey)
        let newKey = try #require(server.requested?.publicKey)
        #expect(newKey != copiedKey)
        #expect(server.removed == [newKey], "the device the switch had added is removed again")
    }

    @Test func `should say the device is on the stranger's member when their approval was overtaken by keeping the key, and can't be removed`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.approveFailure = .deviceTooNew
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        server.holdsApprovals = true
        server.approvals = [.success(.approved(MemberSummary(username: "stranger", onBoard: nil, days: [], visible: true)))]
        let finishing = Task { try await copy.becomeOwnDevice() }
        await heldAtServer()
        try copy.keepKeyHere()
        server.removeFailure = .unreachable
        server.holdsApprovals = false
        server.release()

        let newKey = try #require(server.requested?.publicKey)
        await #expect(throws: LeaderboardError.deviceLeftBehind(DeviceKey(newKey), ours: false)) { try await finishing.value }

        #expect(!copy.holdsCopiedKey)
        #expect(copy.username?.value == "tokenwhale")
        #expect(try storedKey == copiedKey)
    }

    @Test func `should remove the device another Mac approved when the person had chosen to keep the key meanwhile`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.approveFailure = .deviceTooNew
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        server.holdsApprovals = true
        server.approvals = [.success(.approved(server.summary))]
        let finishing = Task { try await copy.becomeOwnDevice() }
        await heldAtServer()
        #expect(server.isHolding, "waiting for another device to approve the code")

        try copy.keepKeyHere()
        server.holdsApprovals = false
        server.release()
        await #expect(throws: LeaderboardError.notOffered) { try await finishing.value }

        #expect(!copy.holdsCopiedKey)
        #expect(try storedKey == copiedKey)
        #expect(server.removed == [server.requested?.publicKey])
    }

    /// A device the switch added stays on the member when the server won't
    /// remove it: the person is told whose member it is on, and who can
    /// remove it, since this Mac kept no key for it.
    @Test func `should say which device stayed on the member when a late switch can't remove the one it added`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.holdsApprovals = true
        server.approvals = [.success(.approved(server.summary))]
        let switching = Task { try await copy.becomeOwnDevice() }
        await heldAtServer()
        try copy.keepKeyHere()
        server.removeFailure = .unreachable
        server.holdsApprovals = false
        server.release()

        let newKey = try #require(server.requested?.publicKey)
        await #expect(throws: LeaderboardError.deviceLeftBehind(DeviceKey(newKey), ours: true)) { try await switching.value }

        #expect(!copy.holdsCopiedKey, "the person's answer stands")
        #expect(try storedKey == copiedKey)
        #expect(server.removed.isEmpty)
    }

    @Test func `should say so when it can't remove itself from the stranger a leaked code was approved by`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.approveFailure = .deviceTooNew
        await #expect(throws: LeaderboardError.deviceTooNew) { try await copy.becomeOwnDevice() }
        server.approvals = [.success(.approved(MemberSummary(username: "stranger", onBoard: nil, days: [], visible: true)))]
        server.removeFailure = .unreachable

        let newKey = try #require(server.requested?.publicKey)
        await #expect(throws: LeaderboardError.deviceLeftBehind(DeviceKey(newKey), ours: false)) { try await copy.becomeOwnDevice() }

        #expect(copy.holdsCopiedKey)
        #expect(copy.username?.value == "tokenwhale")
        #expect(try storedKey == copiedKey)
        #expect(copy.ownDeviceRequest == nil)
    }

    @Test func `should stay a copy, with its key, when the server refuses the new device`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.requestFailure = .deviceLimit

        await #expect(throws: LeaderboardError.deviceLimit) { try await copy.becomeOwnDevice() }

        #expect(copy.holdsCopiedKey)
        #expect(copy.ownDeviceRequest == nil)
        #expect(try storedKey == copiedKey)
        #expect(copy.uploadCredentials == nil)
    }

    @Test func `should stay a copy, the request kept, when this Mac can't store the new key, and finish on a second try`() async throws {
        let copy = try await copied()
        let copiedKey = try storedKey
        server.approvals = [.success(.approved(server.summary))]
        keys.refusesSaving = true

        await #expect(throws: LeaderboardError.keyNotKept) { try await copy.becomeOwnDevice() }

        #expect(copy.holdsCopiedKey)
        #expect(try storedKey == copiedKey, "the copied key still signs")
        let member = try #require(Username("tokenwhale"))
        #expect(copy.ownDeviceRequest?.stage == .approved(member: member))

        keys.refusesSaving = false
        try await copy.becomeOwnDevice()

        #expect(!copy.holdsCopiedKey)
        #expect(try storedKey == server.requested?.publicKey)
        #expect(server.requests == 1)
    }

    @Test func `should offer neither answer while the key is this Mac's own`() async throws {
        let member = try await joined()

        #expect(throws: LeaderboardError.notOffered) { try member.keepKeyHere() }
        await #expect(throws: LeaderboardError.notOffered) { try await member.becomeOwnDevice() }
        #expect(server.requests == 0)
    }

    @Test func `should forget the hash with the key when leaving`() async throws {
        let member = try await joined()

        try await member.leave()

        #expect(settings.record == nil)
        #expect(!launch().holdsCopiedKey)
    }
}

private extension LeaderboardRecord {
    /// This record with another hash beside its key.
    func with(machine: String?) -> LeaderboardRecord {
        LeaderboardRecord(username: username, sharing: sharing, visible: visible, lastUpload: lastUpload,
                          sharesCountry: sharesCountry, globeHintDismissed: globeHintDismissed, link: link,
                          refused: refused, shownDevices: shownDevices, machine: machine)
    }
}
