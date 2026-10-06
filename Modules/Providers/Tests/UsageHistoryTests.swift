import DataSources
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
            let day = Calendar.current.date(byAdding: .day, value: -entry.daysAgo, to: Date())!
            let at = entry.daysAgo == 0 ? Date() : Calendar.current.startOfDay(for: day).addingTimeInterval(43_200)
            return #"{"at":\#(at.timeIntervalSince1970),"tokens":1000,"cost":\#(entry.cost)}"#
        }
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("log.jsonl"), atomically: true, encoding: .utf8)
    }

    private func login(_ id: String) -> ProviderAccountConfig {
        ProviderAccountConfig(accountId: id, label: "", email: nil, probeConfig: ["directory": "/tmp/\(id)"])
    }

    // MARK: - Reading

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

        #expect(history.lastThirtyDays.count == 30)
        #expect(history.lastThirtyDays.first?.totalCost == 7)
        #expect(history.lastThirtyDays.suffix(2).map(\.totalCost) == [41, 14])
    }

    @Test
    func `should show no chart when nothing was used in thirty days`() async {
        let history = history()

        await history.read()

        #expect(history.lastThirtyDays.isEmpty)
    }

    @Test
    func `should show every day of a range, used or not`() async throws {
        try log([("14", 0), ("41", 1)])

        let days = await history().days(in: .last(30))

        #expect(days.count == 30)
        #expect(days.map(\.totalCost).suffix(2) == [41, 14])
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
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
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

    // MARK: - Kept days

    /// A usage history's fingerprint names how its days were summed: when it
    /// changes, every kept day is summed again, a month of logs read anew. These
    /// are the built-in definitions' fingerprints as released. Price files are
    /// left out: a new price list re-sums the days, and is meant to.
    @Test
    func `should keep the days every built-in usage history has already summed`() throws {
        let home = URL(fileURLWithPath: "/Users/someone")
        func fingerprint(_ definition: UsageLog.Definition?) throws -> String {
            DataSources.makeUsageLog(try #require(definition), environment: { _ in nil }, homeDirectory: home).fingerprint
        }
        let claude = try ProviderFactory.builtIn("claude")
        let codex = try ProviderFactory.builtIn("codex")

        #expect(try fingerprint(claude.usageHistory) == "b3bcc70b596fd9b04e17e3db8ad24d09352051cfd8fbac03070d464826171024")
        #expect(try fingerprint(claude.usageHistory(forAccount: ["configDirectory": "/Users/someone/work-claude"]))
            == "931d7ea6e4403964a2af69dd0de2d289ea13c65df6955d337b33e52173cc3f25")
        #expect(try fingerprint(claude.usageHistory?.otherApps?.first?.definition)
            == "d43e7240f0b32898243293138562cd3503f2a69619691664482038c86e360427")
        #expect(try fingerprint(codex.usageHistory) == "2db943b5a7ea6de29b14f66f92d48f028df8f2a176923d0ac3c9be7d1cb8b8ac")
        #expect(try fingerprint(codex.usageHistory(forAccount: ["codexHome": "/Users/someone/work-codex"]))
            == "f64c646a4632e6262d600ca716d13a0addcf792e9e569bfaec672b9cf7cc05b7")
        #expect(try fingerprint(ProviderFactory.builtIn("mistral").usageHistory)
            == "3e1157e243aa7b8bf21ff21cdab66d73f885f72bf7bd7f0c57dee7b56543bf0d")
    }
}

/// Kept days in memory, by key.
private final class InMemoryLedgerStore: LedgerStore, @unchecked Sendable {
    private var pages: [String: LedgerPage] = [:]
    var keys: [String] { Array(pages.keys) }
    func load(_ key: String) -> LedgerPage? { pages[key] }
    func save(_ page: LedgerPage, for key: String) { pages[key] = page }
}
