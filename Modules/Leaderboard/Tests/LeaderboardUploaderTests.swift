import Foundation
import Mockable
import Testing
@testable import Leaderboard
import Quotas

@MainActor
@Suite
struct LeaderboardUploaderTests {
    private let api = MockLeaderboardAPI.accepting()
    private let keys = InMemorySigningKeyStore()
    private let settings = InMemoryLeaderboardSettings()
    private let logs = FakeTokenLogs()
    private let calendar = LeaderboardFixtures.calendar
    private var now = LeaderboardFixtures.date(4, hour: 15)

    private func membership() -> LeaderboardMembership {
        LeaderboardMembership(api: api, keys: keys, settings: settings, logs: logs, machine: MockMachineIdentity.named("MacBook Pro"),
                              calendar: calendar)
    }

    private func uploader(_ membership: LeaderboardMembership) -> LeaderboardUploader {
        let now = now
        return LeaderboardUploader(membership: membership, logs: logs, api: api, calendar: calendar, now: { now })
    }

    private func joined() async throws -> LeaderboardMembership {
        let membership = membership()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        return membership
    }

    @Test func `should send the last thirty days the first time`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(membership.lastUpload == now)
        #expect(settings.record?.lastUpload == now)
    }

    @Test func `should read the last thirty days, and send from the day of the last upload on with the days the server took before it left out`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), sent: [.claude(2, 10), .claude(3, 10)])
        logs.logins = [LoginDays(providerId: "claude", days: (2...4).map { LeaderboardFixtures.stat(day: $0, input: 10) })]
        let sent = refusing([])

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(sent.first?.map(\.day) == ["2026-10-03", "2026-10-04"])
    }

    @Test func `should catch up thirty days at most when the Mac slept for weeks`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(1, month: 8))

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
    }

    @Test func `should keep where it was and say why when an upload can't reach the server`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        let uploader = uploader(membership)

        await uploader.uploadDue()

        #expect(membership.lastUpload == nil)
        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should clear the last error once an upload goes through`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        let uploader = uploader(membership)
        await uploader.uploadDue()

        api.reset([.given])
        given(api).upload(.any, as: .any).willReturn([])
        await uploader.uploadDue()

        #expect(uploader.lastError == nil)
        #expect(membership.lastUpload == now)
    }

    @Test func `should forget the membership and this Mac's key when the server no longer knows the person`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unauthorized)

        await uploader(membership).uploadDue()

        #expect(!membership.isJoined)
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `should forget the membership and say which device removed this one when the server refuses its key for that`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.removed(by: DeviceRef(publicKey: DeviceKey("k2"), label: DeviceLabel("Mac mini")!)))

        await uploader(membership).uploadDue()

        #expect(!membership.isJoined)
        #expect(membership.removedBy == DeviceRef(publicKey: DeviceKey("k2"), label: DeviceLabel("Mac mini")!))
        #expect(keys.stored == nil)
        #expect(settings.record == nil)
    }

    @Test func `should send the last thirty days once a device added to the member joins`() async throws {
        let server = DeviceServer()
        server.approvals = [.success(.approved(server.summary))]
        let membership = LeaderboardMembership(api: server, keys: keys, settings: settings, logs: logs,
                                               machine: MockMachineIdentity.named("Mac mini"), calendar: calendar)
        let request = try await membership.requestToJoin()
        _ = try await request.waitForApproval()
        try membership.join(through: request, sharing: ["claude"])
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]

        let now = now
        await LeaderboardUploader(membership: membership, logs: logs, api: server, calendar: calendar, now: { now }).uploadNow()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(membership.lastUpload == now)
    }

    @Test func `should count as up to date when there is nothing to send`() async throws {
        let membership = try await joined()

        await uploader(membership).uploadDue()

        #expect(membership.lastUpload == now)
    }

    @Test func `should not upload again within an hour of the last upload`() async throws {
        let membership = try await joined()
        let last = now.addingTimeInterval(-59 * 60)
        membership.recordUpload(at: last)

        await uploader(membership).uploadDue()

        #expect(logs.askedFor == nil)
        #expect(membership.lastUpload == last)
    }

    @Test func `should upload again once the last upload is an hour old`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: now.addingTimeInterval(-60 * 60))

        await uploader(membership).uploadDue()

        #expect(membership.lastUpload == now)
    }

    @Test func `should upload at once when the person asks, even within the hour`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: now.addingTimeInterval(-5 * 60))

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(membership.lastUpload == now)
    }

    // MARK: Nothing new to send

    /// One uploader across several asks, its clock moved between them.
    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func uploader(_ membership: LeaderboardMembership, clock: Clock) -> LeaderboardUploader {
        LeaderboardUploader(membership: membership, logs: logs, api: api, calendar: calendar, now: { clock.now })
    }

    /// Joined, one day of Claude tokens sent once, and the server unreachable from then on:
    /// whatever upload follows succeeds only if it stays home.
    private func sentOnce(at start: Date) async throws -> (LeaderboardMembership, LeaderboardUploader, Clock) {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 10)])]
        let clock = Clock(start)
        let uploader = uploader(membership, clock: clock)
        await uploader.uploadDue()
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)
        return (membership, uploader, clock)
    }

    @Test func `should count as up to date without asking the server when an hour brought nothing new`() async throws {
        let (membership, uploader, clock) = try await sentOnce(at: now)

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == nil)
        #expect(membership.lastUpload == clock.now)
    }

    @Test func `should send again when the day's tokens grew`() async throws {
        let (_, uploader, clock) = try await sentOnce(at: now)
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 4, input: 25)])]

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should send the same days again on a new day, so the server's periods move with it`() async throws {
        let (_, uploader, clock) = try await sentOnce(at: LeaderboardFixtures.date(4, hour: 23))

        clock.now = LeaderboardFixtures.date(5, hour: 0).addingTimeInterval(5 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should always send when the person asks, even with nothing new`() async throws {
        let (_, uploader, clock) = try await sentOnce(at: now)

        clock.now = now.addingTimeInterval(5 * 60)
        await uploader.uploadNow()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should send everything after joining again, though the days are the same`() async throws {
        let (membership, uploader, clock) = try await sentOnce(at: now)
        given(api).leave(as: .any).willReturn(())
        given(api).join(username: .any, publicKey: .any, label: .any).willReturn(())
        try await membership.leave()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
    }

    @Test func `should read and send nothing when the person hasn't joined`() async {
        await uploader(membership()).uploadDue()

        #expect(logs.askedFor == nil)
    }

    // MARK: - A refused day

    private static let overCap = RefusedDay(provider: "claude", day: "2026-10-01", reason: "cap")

    /// The days each upload sent, kept from whatever thread the mock answers on.
    private final class SentDays: @unchecked Sendable {
        private let lock = NSLock()
        private var uploads: [[DailyTokens]] = []

        func append(_ days: [DailyTokens]) { lock.withLock { uploads.append(days) } }
        var first: [DailyTokens]? { lock.withLock { uploads.first } }
    }

    /// Answers `refused` to every upload, and keeps the days each one sent. The answer is
    /// `@Sendable`: the mock calls it off the main actor this suite runs on.
    private func refusing(_ refused: [RefusedDay]) -> SentDays {
        let sent = SentDays()
        api.reset([.given])
        given(api).upload(.any, as: .any).willProduce { @Sendable days, _ in
            sent.append(days)
            return refused
        }
        return sent
    }

    @Test func `should keep a refused day and still send the others, moving on as for a good upload`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 10),
                                                                LeaderboardFixtures.stat(day: 4, input: 10)])]
        let sent = refusing([Self.overCap])
        let uploader = uploader(membership)

        await uploader.uploadDue()

        #expect(sent.first?.map(\.day) == ["2026-10-01", "2026-10-04"])
        #expect(membership.lastUpload == now)
        #expect(membership.refused == [Self.overCap])
        #expect(settings.record?.refused == [Self.overCap])
        #expect(uploader.lastError == nil)
    }

    @Test func `should send a refused day again on the hour, though nothing else is new`() async throws {
        let membership = try await joined()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 10),
                                                                LeaderboardFixtures.stat(day: 4, input: 10)])]
        _ = refusing([Self.overCap])
        let clock = Clock(now)
        let uploader = uploader(membership, clock: clock)
        await uploader.uploadDue()
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(LeaderboardError.unreachable)

        clock.now = now.addingTimeInterval(60 * 60)
        await uploader.uploadDue()

        #expect(uploader.lastError == .unreachable)
        #expect(membership.refused == [Self.overCap])
    }

    @Test func `should send a refused day again with the next upload, and none of the days in between`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), sent: [.claude(2, 10), .claude(3, 10)], refused: [Self.overCap])
        logs.logins = [LoginDays(providerId: "claude", days: (1...4).map { LeaderboardFixtures.stat(day: $0, input: 10) })]
        let sent = refusing([])

        await uploader(membership).uploadNow()

        #expect(sent.first?.map(\.day) == ["2026-10-01", "2026-10-03", "2026-10-04"])
        #expect(membership.refused.isEmpty)
    }

    @Test func `should stop sending a refused day once it is more than thirty days old`() async throws {
        let membership = try await joined()
        let tooOld = RefusedDay(provider: "claude", day: "2026-09-01", reason: "cap")
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), refused: [tooOld])
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, month: 9, input: 10),
                                                                LeaderboardFixtures.stat(day: 4, input: 10)])]
        let sent = refusing([])

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == DateRange.last(30, endingOn: now, calendar: calendar))
        #expect(sent.first?.map(\.day) == ["2026-10-04"])
        #expect(membership.refused.isEmpty)
    }

    @Test(arguments: [LeaderboardError.unreachable, .rejected("The leaderboard answered with something unreadable.")])
    func `should keep a refused day to send again when an upload fails, unreachable or unreadable`(failure: LeaderboardError) async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(3, hour: 23), refused: [Self.overCap])
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 10)])]
        api.reset([.given])
        given(api).upload(.any, as: .any).willThrow(failure)

        await uploader(membership).uploadNow()

        #expect(membership.refused == [Self.overCap])
        #expect(settings.record?.refused == [Self.overCap])
        #expect(membership.lastUpload == LeaderboardFixtures.date(3, hour: 23))
    }

    // MARK: - On and off

    @Test func `should read and send nothing, and keep where it stopped, while the Leaderboard is off`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(2))
        membership.turnOff()

        await uploader(membership).uploadNow()

        #expect(logs.askedFor == nil)
        #expect(membership.lastUpload == LeaderboardFixtures.date(2))
    }

    @Test func `should catch up from where it stopped once the Leaderboard is back on, with the earlier days that grew while off`() async throws {
        let membership = try await joined()
        membership.recordUpload(at: LeaderboardFixtures.date(2), sent: [.claude(1, 10), .claude(2, 10)])
        membership.turnOff()
        logs.logins = [LoginDays(providerId: "claude", days: [LeaderboardFixtures.stat(day: 1, input: 25),
                                                                LeaderboardFixtures.stat(day: 2, input: 10),
                                                                LeaderboardFixtures.stat(day: 3, input: 10)])]
        await uploader(membership).uploadDue()
        let sent = refusing([])

        membership.turnOn()
        await uploader(membership).uploadDue()

        #expect(sent.first == [.claude(1, 25), .claude(2, 10), .claude(3, 10)])
        #expect(membership.lastUpload == now)
    }

    // MARK: - An earlier day that appears or grows (design §2a, #680)

    private let server = DeviceServer()
    private static let dayOneOverCap = RefusedDay(provider: "claude", day: "2026-10-01", reason: "cap")

    /// Joined on `server`, sharing `providers`.
    private func member(sharing providers: Set<String> = ["claude"]) async throws -> LeaderboardMembership {
        let membership = relaunched()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: providers)
        return membership
    }

    /// The app launched again, over the same key and settings.
    private func relaunched() -> LeaderboardMembership {
        LeaderboardMembership(api: server, keys: keys, settings: settings, logs: logs,
                              machine: MockMachineIdentity.named("MacBook Pro"), calendar: calendar)
    }

    /// A member from before `sent` was kept, launched after the update: its
    /// record says when it last uploaded, and nothing of what the server took.
    private func updated(lastUpload: Date, refused: [RefusedDay] = []) async throws -> LeaderboardMembership {
        _ = try await member()
        let record = try #require(settings.record)
        settings.record = LeaderboardRecord(username: record.username, sharing: record.sharing, visible: record.visible,
                                            lastUpload: lastUpload, refused: refused, machine: record.machine)
        return relaunched()
    }

    private func uploader(_ membership: LeaderboardMembership, on server: DeviceServer, clock: Clock) -> LeaderboardUploader {
        LeaderboardUploader(membership: membership, logs: logs, api: server, calendar: calendar, now: { clock.now })
    }

    /// One login's days of `provider`, each day's tokens all input.
    private func login(_ provider: String, month: Int = 10, _ days: [Int: Int]) -> LoginDays {
        LoginDays(providerId: provider, days: days.keys.sorted().map { LeaderboardFixtures.stat(day: $0, month: month, input: days[$0]!) })
    }

    /// Each upload the server got, as `provider MM-dd total` per day.
    private var uploads: [[String]] {
        server.uploads.map { $0.days.map { "\($0.provider) \($0.day.suffix(5)) \($0.total)" } }
    }

    private func hours(_ count: Double) -> Date {
        now.addingTimeInterval(count * 60 * 60)
    }

    @Test func `should send a provider's earlier days once when it is shared after the first upload`() async throws {
        let membership = try await member()
        logs.logins = [login("claude", [4: 10]), login("codex", [1: 20, 2: 30])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()

        try membership.share("codex")
        clock.now = hours(1)
        await uploader.uploadDue()
        clock.now = hours(2)
        await uploader.uploadDue()

        #expect(uploads == [["claude 10-04 10"], ["codex 10-01 20", "codex 10-02 30", "claude 10-04 10"]])
    }

    @Test func `should send a login's earlier days once when it is added after the first upload, summed with the provider's other login`() async throws {
        let membership = try await member()
        logs.logins = [login("claude", [1: 20, 4: 10])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()

        logs.logins.append(login("claude", [1: 30, 2: 15]))
        clock.now = hours(1)
        await uploader.uploadDue()
        clock.now = hours(2)
        await uploader.uploadDue()

        #expect(uploads == [["claude 10-01 20", "claude 10-04 10"],
                            ["claude 10-01 50", "claude 10-02 15", "claude 10-04 10"]],
                "a day first seen after the upload goes too, and a grown one with its whole total, never the difference")
    }

    @Test func `should send yesterday again with its new total when a session across midnight grows it after the upload moved to today`() async throws {
        let membership = try await member()
        let clock = Clock(LeaderboardFixtures.date(4, hour: 23))
        let uploader = uploader(membership, on: server, clock: clock)
        logs.logins = [login("claude", [4: 100])]
        await uploader.uploadDue()
        clock.now = LeaderboardFixtures.date(5, hour: 0).addingTimeInterval(35 * 60)
        logs.logins = [login("claude", [4: 120, 5: 5])]
        await uploader.uploadDue()

        clock.now = LeaderboardFixtures.date(5, hour: 1).addingTimeInterval(40 * 60)
        logs.logins = [login("claude", [4: 150, 5: 5])]
        await uploader.uploadDue()

        #expect(uploads.count == 3)
        #expect(uploads.last == ["claude 10-04 150", "claude 10-05 5"])
    }

    @Test func `should send from the last upload's day after days asleep, with the earlier days that grew or appeared and none that didn't`() async throws {
        let membership = try await member()
        membership.recordUpload(at: LeaderboardFixtures.date(1, hour: 9),
                                sent: [.claude(28, month: 9, 10), .claude(30, month: 9, 10), .claude(1, 5)])
        logs.logins = [login("claude", month: 9, [28: 10, 29: 7, 30: 12]), login("claude", [1: 6, 3: 4, 4: 9])]

        await uploader(membership, on: server, clock: Clock(now)).uploadDue()

        #expect(uploads == [["claude 09-29 7", "claude 09-30 12", "claude 10-01 6", "claude 10-03 4", "claude 10-04 9"]])
    }

    @Test func `should not send an earlier day that reads smaller, and send it again only once it grows past what the server took`() async throws {
        let membership = try await member()
        logs.logins = [login("claude", [1: 100, 4: 10])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()

        for (hour, total) in [(1.0, 50), (2, 80)] {
            logs.logins = [login("claude", [1: total, 4: 10])]
            clock.now = hours(hour)
            await uploader.uploadDue()
        }
        #expect(settings.record?.sent?.first == SentDay(provider: "claude", day: "2026-10-01", total: 100))
        logs.logins = [login("claude", [1: 120, 4: 10])]
        clock.now = hours(3)
        await uploader.uploadDue()

        #expect(uploads == [["claude 10-01 100", "claude 10-04 10"], ["claude 10-01 120", "claude 10-04 10"]])
    }

    @Test func `should keep what the server took of a day until two days after it leaves the thirty, so a move to a zone behind doesn't send it smaller`() async throws {
        let membership = try await member()
        let early = SentDay(provider: "claude", day: "2026-09-04", total: 100)
        let clock = Clock(LeaderboardFixtures.date(3))
        let uploader = uploader(membership, on: server, clock: clock)
        logs.logins = [login("claude", month: 9, [4: 100]), login("claude", [3: 10])]
        await uploader.uploadDue()

        clock.now = LeaderboardFixtures.date(5)
        await uploader.uploadNow()
        #expect(settings.record?.sent?.contains(early) == true, "two days out of the thirty, it is still kept")
        clock.now = LeaderboardFixtures.date(3, hour: 18)
        logs.logins = [login("claude", month: 9, [4: 50]), login("claude", [3: 10])]
        await uploader.uploadNow()
        #expect(uploads.count == 2, "back in the thirty, it reads 50 where the server took 100: nothing goes")

        clock.now = LeaderboardFixtures.date(6)
        await uploader.uploadNow()
        #expect(settings.record?.sent?.contains(early) == false)
    }

    @Test func `should not count a refused day as taken, and count it once the server takes it`() async throws {
        let membership = try await member()
        logs.logins = [login("claude", [1: 10, 4: 10])]
        server.uploadAnswer = .success([Self.dayOneOverCap])
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()
        #expect(settings.record?.sent == [SentDay(provider: "claude", day: "2026-10-04", total: 10)])
        #expect(membership.refused == [Self.dayOneOverCap])

        server.uploadAnswer = .success([])
        clock.now = hours(1)
        await uploader.uploadDue()

        #expect(uploads.last == ["claude 10-01 10", "claude 10-04 10"])
        #expect(settings.record?.sent == [SentDay(provider: "claude", day: "2026-10-01", total: 10),
                                          SentDay(provider: "claude", day: "2026-10-04", total: 10)])
    }

    @Test func `should not send a refused earlier day that now reads below what the server took, and stop retrying it`() async throws {
        let membership = try await member()
        let clock = Clock(LeaderboardFixtures.date(3))
        let uploader = uploader(membership, on: server, clock: clock)
        logs.logins = [login("claude", [1: 100])]
        await uploader.uploadDue()
        clock.now = LeaderboardFixtures.date(4)
        logs.logins = [login("claude", [1: 150])]
        server.uploadAnswer = .success([Self.dayOneOverCap])
        await uploader.uploadDue()
        #expect(membership.refused == [Self.dayOneOverCap])

        server.uploadAnswer = .success([])
        clock.now = LeaderboardFixtures.date(4, hour: 13)
        logs.logins = [login("claude", [1: 50])]
        await uploader.uploadDue()

        #expect(uploads == [["claude 10-01 100"], ["claude 10-01 150"]], "100 taken, 150 refused, 50 read: nothing goes")
        #expect(membership.refused.isEmpty)
        #expect(settings.record?.sent == [SentDay(provider: "claude", day: "2026-10-01", total: 100)])
    }

    @Test func `should record nothing of a failed upload`() async throws {
        let membership = try await member()
        #expect(settings.record?.sent == [], "a join starts with nothing taken, apart from a record from before it was kept")
        logs.logins = [login("claude", [4: 10])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()

        logs.logins = [login("claude", [3: 5, 4: 25])]
        server.uploadAnswer = .failure(.unreachable)
        clock.now = hours(1)
        await uploader.uploadDue()

        #expect(settings.record?.sent == [SentDay(provider: "claude", day: "2026-10-04", total: 10)])
        #expect(membership.lastUpload == now)
    }

    @Test(arguments: [Result<[RefusedDay], LeaderboardError>.success([]), .failure(.unauthorized),
                      .failure(.removed(by: DeviceRef(publicKey: DeviceKey("k2"), label: DeviceLabel("Mac mini")!)))])
    func `should record and forget nothing in a membership joined again while an upload signed by the old key was out`(
        answer: Result<[RefusedDay], LeaderboardError>
    ) async throws {
        let membership = try await member()
        logs.logins = [login("claude", [1: 20, 4: 10])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        server.holdsUploads = true
        server.uploadAnswer = answer
        let upload = Task { await uploader.uploadNow() }
        for _ in 0..<1000 where !server.isHolding { await Task.yield() }

        try await membership.leave()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        server.holdsUploads = false
        server.release()
        await upload.value

        #expect(membership.isJoined && membership.removedBy == nil, "an old key's answer never forgets the new membership")
        #expect(membership.lastUpload == nil)
        #expect(settings.record?.sent == [])
        server.uploadAnswer = .success([])
        clock.now = hours(0.1)
        await uploader.uploadNow()
        #expect(server.uploads.last?.key == membership.credentials?.key.publicKey)
        #expect(uploads.last == ["claude 10-01 20", "claude 10-04 10"], "the new membership's first upload sends its thirty days")
    }

    @Test func `should send nothing more after an update from before what the server took was kept, holding the days before the last upload's`() async throws {
        let membership = try await updated(lastUpload: LeaderboardFixtures.date(3, hour: 23))
        logs.logins = [login("claude", [1: 50, 3: 5, 4: 10])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()
        #expect(uploads == [["claude 10-03 5", "claude 10-04 10"]])
        #expect(settings.record?.heldBefore == "2026-10-03")
        #expect(settings.record?.sent == [SentDay(provider: "claude", day: "2026-10-03", total: 5),
                                          SentDay(provider: "claude", day: "2026-10-04", total: 10)])

        logs.logins = [login("claude", [1: 60, 3: 8, 4: 10])]
        clock.now = hours(1)
        await uploader.uploadDue()

        #expect(uploads.count == 2)
        #expect(uploads.last == ["claude 10-03 8", "claude 10-04 10"],
                "a held day the server holds at 100, read at 50 and then 60, never goes; a day after the cut that grew does")
    }

    @Test func `should send a held day again when the server refused it`() async throws {
        let membership = try await updated(lastUpload: LeaderboardFixtures.date(3, hour: 23), refused: [Self.dayOneOverCap])
        logs.logins = [login("claude", [1: 50, 2: 30, 4: 10])]
        server.uploadAnswer = .success([Self.dayOneOverCap])
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()
        clock.now = hours(1)
        await uploader.uploadDue()

        #expect(uploads == [["claude 10-01 50", "claude 10-04 10"], ["claude 10-01 50", "claude 10-04 10"]])
        #expect(settings.record?.heldBefore == "2026-10-03")
    }

    @Test func `should hold nothing and send thirty days after leaving and joining again`() async throws {
        let membership = try await updated(lastUpload: LeaderboardFixtures.date(3, hour: 23))
        logs.logins = [login("claude", [1: 50, 4: 10])]

        try await membership.leave()
        try await membership.join(as: #require(Username("tokenwhale")), sharing: ["claude"])
        #expect(settings.record?.heldBefore == nil)
        #expect(settings.record?.sent == [])
        await uploader(membership, on: server, clock: Clock(now)).uploadDue()

        #expect(uploads == [["claude 10-01 50", "claude 10-04 10"]])
    }

    @Test func `should remember what the server took across a relaunch`() async throws {
        let membership = try await member()
        logs.logins = [login("claude", [1: 100, 4: 10])]
        await uploader(membership, on: server, clock: Clock(now)).uploadDue()

        let again = relaunched()
        logs.logins = [login("claude", [1: 120, 4: 10])]
        await uploader(again, on: server, clock: Clock(hours(1))).uploadDue()

        #expect(uploads.last == ["claude 10-01 120", "claude 10-04 10"])
        #expect(settings.record?.sent == [SentDay(provider: "claude", day: "2026-10-01", total: 120),
                                          SentDay(provider: "claude", day: "2026-10-04", total: 10)])
    }

    @Test func `should send only the days that grew meanwhile when a provider is shared again`() async throws {
        let membership = try await member(sharing: ["claude", "codex"])
        logs.logins = [login("claude", [4: 10]), login("codex", [1: 20])]
        let clock = Clock(now)
        let uploader = uploader(membership, on: server, clock: clock)
        await uploader.uploadDue()
        membership.stopSharing("codex")
        clock.now = hours(1)
        await uploader.uploadDue()

        try membership.share("codex")
        logs.logins = [login("claude", [4: 10]), login("codex", [1: 20, 2: 5])]
        clock.now = hours(2)
        await uploader.uploadDue()

        #expect(uploads == [["codex 10-01 20", "claude 10-04 10"], ["codex 10-02 5", "claude 10-04 10"]])
    }
}
