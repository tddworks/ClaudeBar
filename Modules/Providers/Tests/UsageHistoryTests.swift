@testable import DataSources
import Quotas
import Foundation
import Providers
import Testing

/// *TODAY'S USAGE* — what a login used, day by day, read from its tool's own
/// logs. The login owns it: `account.usageHistory`, `nil` when the provider
/// offers none or the login's logs aren't read.
@MainActor
@Suite
struct UsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func history() -> UsageHistory {
        let definition = UsageLog.Definition(records: UsageLog.Records(
            files: "~/.acme/*.jsonl", at: "$.at", tokens: UsageLog.Tokens(total: "$.tokens"), cost: "$.cost"))
        return UsageHistory(log: DataSources.makeUsageLog(definition, environment: { _ in nil }, homeDirectory: home))
    }

    private func log(_ entries: [(cost: String, daysAgo: Int)]) throws {
        let dir = home.appendingPathComponent(".acme")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = entries.map { entry -> String in
            let day = DataSources.calendar().date(byAdding: .day, value: -entry.daysAgo, to: Date())!
            let at = entry.daysAgo == 0 ? Date() : DataSources.calendar().startOfDay(for: day).addingTimeInterval(43_200)
            return #"{"at":\#(at.timeIntervalSince1970),"tokens":1000,"cost":\#(entry.cost)}"#
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("log.jsonl"), atomically: true, encoding: .utf8)
    }

    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: "", email: nil, probeConfig: ["directory": "/tmp/\(id)"])
    }

    // MARK: - Reading

    @Test
    func `should offer cost when a day of the last thirty holds one, even if today and yesterday were idle`() async throws {
        try log([("14", 5)])
        let history = history()

        await history.read()

        #expect(history.hasCost)
    }

    @Test
    func `should offer no cost when every day prices at zero`() async throws {
        try log([("0", 0), ("0", 1), ("0", 7)])
        let history = history()

        await history.read()

        #expect(!history.hasCost)
    }

    @Test
    func `should show today's usage against yesterday's`() async throws {
        try log([("14", 0), ("41", 1)])
        let history = history()

        await history.read()

        #expect(history.report?.today.totalCost == 14)
        #expect(history.report?.previous.totalCost == 41)
    }

    @Test
    func `should show no usage history when nothing was used today or yesterday`() async {
        let history = history()

        await history.read()

        #expect(history.report == nil)
    }

    @Test
    func `should show yesterday's usage and an empty today when only yesterday was used`() async throws {
        try log([("41", 1)])
        let history = history()

        await history.read()

        #expect(history.report?.previous.totalCost == 41)
        #expect(history.report?.today.isEmpty == true)
    }

    @Test
    func `should chart the last thirty days, oldest first, leaving out older days`() async throws {
        try log([("14", 0), ("41", 1), ("7", 29), ("99", 30)])
        let history = history()

        await history.read()

        #expect(history.lastThirtyDays?.stats.count == 30)
        #expect(history.lastThirtyDays?.stats.first?.totalCost == 7)
        #expect(history.lastThirtyDays?.stats.suffix(2).map(\.totalCost) == [41, 14])
    }

    @Test
    func `should show no chart when nothing was used in thirty days`() async {
        let history = history()

        await history.read()

        #expect(history.lastThirtyDays == nil)
    }

    @Test
    func `should show every day of a range, used or not`() async throws {
        try log([("14", 0), ("41", 1)])

        let days = await history().days(in: .last(30, calendar: DataSources.calendar()))

        #expect(days.stats.count == 30)
        #expect(days.stats.map(\.totalCost).suffix(2) == [41, 14])
    }

    // MARK: - The login owns it

    @Test
    func `should give the default login the provider's usage history`() throws {
        let history = history()
        let provider = try ProviderFactory.make("grok", settings: InMemoryProviderSettings(), usageHistory: history)

        #expect(provider.defaultAccount.usageHistory === history)
    }

    @Test
    func `should show no usage history for an added login whose logs are not read`() throws {
        let provider = try ProviderFactory.make("grok", settings: InMemoryProviderSettings(), accounts: [login("work")],
                                          usageHistory: history())

        #expect(provider.accounts.first { !$0.isDefault }?.usageHistory == nil)
    }

    @Test
    func `should show no usage history when the provider offers none`() throws {
        let provider = try ProviderFactory.make("grok", settings: InMemoryProviderSettings())

        #expect(provider.defaultAccount.usageHistory == nil)
    }

    // MARK: - Other apps

    private func desk(_ tokens: Int, daysAgo: Int = 0) throws {
        let day = DataSources.calendar().date(byAdding: .day, value: -daysAgo, to: Date())!
        let dir = home.appendingPathComponent("Desk")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"at":\#(day.timeIntervalSince1970),"n":\#(tokens)}"#.write(to: dir.appendingPathComponent("today.json"), atomically: true, encoding: .utf8)
    }

    private var deskDefinition: UsageLog.Definition {
        UsageLog.Definition(
            records: UsageLog.Records(files: "~/.acme/*.jsonl", at: "$.at", tokens: UsageLog.Tokens(total: "$.tokens"), cost: "$.cost"),
            otherApps: [UsageLog.OtherApp(label: "Desk", records: UsageLog.Records(
                files: "~/Desk/today.json", format: .json, at: "$.at", tokens: UsageLog.Tokens(total: "$.n")))])
    }

    private func historyWithDesk(ledger: @escaping (String) -> DayLedger? = { _ in nil }) -> UsageHistory {
        UsageHistory(deskDefinition, login: "acme",
                     log: { DataSources.makeUsageLog($0, environment: { _ in nil }, homeDirectory: home) }, ledger: ledger)
    }

    @Test
    func `should show each other app's usage under its own name, apart from the login's`() async throws {
        try log([("14", 0)])
        try desk(74_422)
        let history = historyWithDesk()

        await history.read()

        let desk = try #require(history.otherApps.first)
        #expect(desk.label == "Desk")
        #expect(desk.report?.today.totalTokens == 74_422)
        #expect(desk.knowsCost == false)
        #expect(history.usedOtherApps.map(\.label) == ["Desk"])
        #expect(history.hasUsage)
        #expect(history.label == nil)
        #expect(history.report?.today.totalTokens == 1000)
    }

    @Test
    func `should have usage to show when only another app was used`() async throws {
        try desk(74_422)
        let history = historyWithDesk()

        await history.read()

        #expect(history.report == nil)
        #expect(history.hasUsage)
    }

    @Test
    func `should show nothing for another app used neither today nor yesterday`() async throws {
        try desk(500, daysAgo: 3)
        let history = historyWithDesk()

        await history.read()

        #expect(history.otherApps.first?.report == nil)
        #expect(history.usedOtherApps.isEmpty)
        #expect(!history.hasUsage)
    }

    @Test
    func `should keep each other app's days apart from the login's`() async throws {
        let store = InMemoryLedgerStore()
        try desk(500, daysAgo: 2)
        let history = historyWithDesk(ledger: { DayLedger(store: store, key: $0) })

        await history.read()

        #expect(store.keys.sorted() == ["acme", "acme/Desk"])
    }

    // MARK: - A custom provider's own logs (the demo home)

    /// `scripts/demo-screenshots.sh` writes a custom provider into the demo
    /// home's `~/.claudebar/providers`, with a `usageHistory` over thirty-one
    /// days of sample logs — the definition, not a built-in, is what says
    /// where they are. Written as a value, not as text: the folder is a
    /// Windows path there, and a backslash in a JSON string is an escape.
    private func writeDemoProvider() throws {
        let dir = home.appendingPathComponent(".claudebar/providers")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profile: [String: Any] = ["id": "custom-a-claude", "name": "Claude", "origin": "custom",
                                      "links": [String: Any](), "look": [String: Any]()]
        let records: [String: Any] = ["files": home.appendingPathComponent("sample-logs/*.jsonl").path,
                                      "format": "jsonLines", "at": "$.at", "id": ["$.id"], "model": "$.model",
                                      "tokens": ["input": "$.input", "output": "$.output", "cacheRead": "$.cacheRead"],
                                      "cost": "$.cost"]
        let quotaSource: [String: Any] = ["kind": "api", "label": "API",
                                          "fetch": ["http": ["url": "http://127.0.0.1:1/"]],
                                          "mapping": ["json": ["quotas": [Any]()]]]
        let definition: [String: Any] = [
            "profile": profile,
            "dataSources": [quotaSource],
            "defaultDataSource": "api",
            "usageHistory": ["records": records, "sessionGap": 1800],
        ]
        try JSONSerialization.data(withJSONObject: definition, options: [.prettyPrinted, .sortedKeys])
            .write(to: dir.appendingPathComponent("custom-a-claude.json"))
    }

    /// Thirty-one days of the demo's sample sessions, one file, as it writes
    /// them. Today's are at `now`, the way `log(_:)` above does: the demo
    /// anchors them seven hours back, which before 07:00 is yesterday's day,
    /// and a fixture that emptied today's cards at four in the morning would
    /// be testing the clock rather than the days.
    private func writeSampleLogs() throws {
        let dir = home.appendingPathComponent("sample-logs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let calendar = DataSources.calendar()
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        for daysAgo in 0...30 {
            let start = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
            for step in 0..<3 {
                let at = daysAgo == 0 ? Date() : start.addingTimeInterval(9 * 3600 + Double(step) * 3600)
                lines.append("""
                {"at":"\(formatter.string(from: at))","id":"sample-\(daysAgo)-\(step)",\
                "model":"claude-sonnet-sample","input":12000,"output":3000,"cacheRead":200000,"cost":0.42}
                """)
            }
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("sample.jsonl"),
                                                atomically: true, encoding: .utf8)
    }

    /// The demo home's own history, made the way the factory makes one.
    private func demoHistory() throws -> UsageHistory {
        try writeDemoProvider()
        let found = try #require(ProviderCatalog(directory: home.appendingPathComponent(".claudebar/providers"))
            .custom().first { $0.id == "custom-a-claude" })
        return UsageHistory(try #require(found.usageHistory), login: "custom-a-claude",
                            log: { DataSources.makeUsageLog($0, environment: { _ in nil }, homeDirectory: home) },
                            ledger: { _ in nil })
    }

    @Test
    func `should show a custom provider's last thirty days from its own sample logs`() async throws {
        try writeSampleLogs()
        let history = try demoHistory()

        await history.read()

        #expect(history.report?.today.isEmpty == false)
        let days = try #require(history.lastThirtyDays)
        #expect(days.stats.count == 30)
        #expect(days.stats.allSatisfy { !$0.isEmpty }, "the demo writes a session every day of the month")
        // The demo's records name a model, so the chart offers its split.
        #expect(days.hasModels)
        #expect(days.lines(of: days.stats[29], in: .cost).map(\.model) == ["claude-sonnet-sample"])
    }

    // MARK: - Kept days

    @Test
    func `should keep an archived day when its file path becomes a portable app data path`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let calendar = DataSources.calendar()
        let now = Date()
        let archived = try #require(calendar.date(byAdding: .day, value: -3, to: now))
        let at = calendar.startOfDay(for: archived).addingTimeInterval(43_200)
        let appData = home.appendingPathComponent("Library/Application Support")
        let file = appData.appendingPathComponent("Desk/log.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"at":\#(at.timeIntervalSince1970),"tokens":500}"#.utf8).write(to: file)
        var platform = Platform.current
        platform.applicationData = { _, _ in appData }
        func make(_ path: String) -> UsageLog {
            let definition = UsageLog.Definition(records: .init(files: path, at: "$.at", tokens: .init(total: "$.tokens")))
            return DataSources.makeUsageLog(definition, platform: platform, environment: { _ in nil },
                                            homeDirectory: home, now: { now })
        }
        let store = InMemoryLedgerStore()
        let range = DateRange.last(5, endingOn: now, calendar: calendar)
        let original = UsageHistory(log: make("~/Library/Application Support/Desk/log.jsonl"),
                                    ledger: DayLedger(store: store, key: "desk"))
        let before = await original.days(in: range)
        #expect(before.stats.first { calendar.isDate($0.date, inSameDayAs: archived) }?.totalTokens == 500)
        // Desktop overwrites its count every day; this archived source is gone.
        try FileManager.default.removeItem(at: file)
        let portable = UsageHistory(log: make("{{platform.appData}}/Desk/log.jsonl"),
                                    ledger: DayLedger(store: store, key: "desk"))
        let after = await portable.days(in: range)
        #expect(after.stats.first { calendar.isDate($0.date, inSameDayAs: archived) }?.totalTokens == 500)
    }
}

/// Kept days in memory, by key.
private final class InMemoryLedgerStore: LedgerStore, @unchecked Sendable {
    private var pages: [String: LedgerPage] = [:]
    var keys: [String] { Array(pages.keys) }
    func load(_ key: String) -> LedgerPage? { pages[key] }
    func save(_ page: LedgerPage, for key: String) { pages[key] = page }
}
