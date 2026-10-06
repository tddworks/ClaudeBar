import Foundation
import Quotas
import Testing
@testable import DataSources

/// A usage log, end to end: the files its glob names, read into records,
/// deduplicated, priced and summed into one stat per local day.
@Suite
struct UsageLogTests {
    static let definition = UsageLog.Definition(
        records: UsageLog.Records(
            files: "~/.acme/sessions/**/*.jsonl",
            where: Match(path: "$.kind", equals: .string("reply")),
            at: "$.at",
            id: ["$.reply.id", "$.request"],
            model: "$.reply.model",
            tokens: UsageLog.Tokens(input: "$.reply.usage.in", output: "$.reply.usage.out",
                                    cacheWrite: "$.reply.usage.cacheIn", cacheRead: "$.reply.usage.cacheHit")
        ),
        prices: UsageLog.Prices(file: "acme-prices.json"),
        freeWhen: UsageLog.FreeWhen(localEndpoint: UsageLog.LocalEndpointRule(file: "~/.acme/config.json", url: [["$.baseURL"]])),
        sessionGap: 1800
    )

    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let calendar = Calendar.current
    private let now = Date()

    private func log(_ definition: UsageLog.Definition = Self.definition) -> UsageLog {
        DataSources.makeUsageLog(definition, scripts: { $0 == "acme-prices.json" ? PriceListTests.file : nil },
                                 environment: { _ in nil }, homeDirectory: home, calendar: calendar, now: { [now] in now })
    }

    private func write(_ lines: [String], to name: String = "project/one.jsonl") throws {
        let url = home.appendingPathComponent(".acme/sessions").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func stamp(_ offset: TimeInterval = 0, daysAgo: Int = 0) -> String {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: daysAgo == 0 ? day.addingTimeInterval(offset) : calendar.startOfDay(for: day).addingTimeInterval(43_200 + offset))
    }

    private func line(model: String = "m-medium-2", id: String? = nil, input: Int = 1000, output: Int = 500,
                      cacheRead: Int = 0, at: String) -> String {
        let identity = id.map { #""request":"q_\#($0)","reply":{"id":"r_\#($0)","#  } ?? #""reply":{"#
        return #"{"kind":"reply",\#(identity)"model":"\#(model)","usage":{"in":\#(input),"out":\#(output),"cacheHit":\#(cacheRead)}},"at":"\#(at)"}"#
    }

    private func today() async -> DailyUsageStat { await log().days(last: 1)[0] }

    @Test func `should show every day of the range, a day with no usage as empty`() async throws {
        try write([line(at: stamp())])
        let days = await log().days(last: 3)
        #expect(days.count == 3)
        #expect(days.map(\.date) == DateRange.last(3, endingOn: now).days())
        #expect(days[0].isEmpty && days[1].isEmpty)
        #expect(days[2].totalTokens == 1500)
    }

    @Test func `should count usage on the day it happened`() async throws {
        try write([line(at: stamp()), line(input: 2000, output: 1000, at: stamp(daysAgo: 1))])
        let days = await log().days(last: 2)
        #expect(days[1].totalTokens == 1500)
        #expect(days[0].totalTokens == 3000)
    }

    @Test func `should show every day empty when nothing is logged`() async {
        #expect(await log().days(last: 2).allSatisfy(\.isEmpty))
    }

    @Test func `should count logs in folders at any depth, and only the files that match`() async throws {
        try write([line(at: stamp())], to: "a/b/c/deep.jsonl")
        try write([line(at: stamp())], to: "notes.txt")
        #expect(await today().totalTokens == 1500)
    }

    // MARK: - Written twice, counted once

    @Test func `should count usage written twice in a log once`() async throws {
        let copy = line(id: "1", at: stamp())
        try write([copy, copy, copy])
        #expect(await today().totalTokens == 1500)
    }

    @Test func `should count the last copy of usage written more than once`() async throws {
        try write([line(id: "1", output: 1, at: stamp()), line(id: "1", output: 1, at: stamp(0.1)), line(id: "1", output: 500, at: stamp(0.9))])
        let today = await today()
        #expect(today.outputTokens == 500)
        #expect(today.totalTokens == 1500)
    }

    @Test func `should count usage copied into another log once`() async throws {
        try write([line(id: "1", at: stamp())], to: "p/one.jsonl")
        try write([line(id: "1", at: stamp())], to: "p/two.jsonl")
        #expect(await today().totalTokens == 1500)
    }

    @Test func `should count every distinct entry, and every entry without an identity`() async throws {
        try write([line(id: "1", at: stamp()), line(id: "2", input: 2000, output: 1000, at: stamp()),
                   line(at: stamp()), line(at: stamp())])
        #expect(await today().totalTokens == 7500)
    }

    // MARK: - Prices

    @Test func `should show the day's cost and cache savings from the price list`() async throws {
        try write([line(input: 1000, output: 500, cacheRead: 1_000_000, at: stamp())])
        let today = await today()
        #expect(today.cacheReadTokens == 1_000_000)
        #expect(today.cachedSavings == Decimal(string: "2.7"))
        #expect(today.totalCost == Decimal(string: "0.3105"))
    }

    @Test func `should show the cost the log gives over any price, with each entry its own session`() async throws {
        let definition = UsageLog.Definition(
            records: UsageLog.Records(files: "~/.acme/sessions/**/*.jsonl", at: "$.at",
                                      tokens: UsageLog.Tokens(total: "$.tokens"), cost: "$.cost"),
            prices: UsageLog.Prices(file: "acme-prices.json")
        )
        try write([#"{"at":"\#(stamp())","tokens":1234,"cost":0.0123}"#])
        let today = await log(definition).days(last: 1)[0]
        #expect(today.totalCost == Decimal(string: "0.0123"))
        #expect(today.totalTokens == 1234)
        // Without a session gap, each record is a session and no working time is known.
        #expect(today.sessionCount == 1)
        #expect(today.workingTime == 0)
    }

    // MARK: - A local route

    private func route(_ url: String) throws {
        let config = home.appendingPathComponent(".acme/config.json")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"baseURL":"\#(url)"}"#.write(to: config, atomically: true, encoding: .utf8)
    }

    @Test func `should cost nothing today for an unlisted model when the tool runs on this Mac`() async throws {
        try route("http://localhost:11434")
        try write([line(model: "acme-internal-7b", at: stamp())])
        #expect(await today().totalCost == 0)
    }

    @Test func `should estimate an unlisted model's cost when the tool runs on a remote gateway`() async throws {
        try route("https://gateway.example.com")
        try write([line(model: "acme-internal-7b", at: stamp())])
        #expect(await today().totalCost == Decimal(string: "0.0105"))
    }

    @Test func `should keep an earlier day's cost when the tool runs on this Mac only now`() async throws {
        try route("http://localhost:11434")
        try write([line(model: "acme-internal-7b", at: stamp(daysAgo: 1))])
        let days = await log().days(last: 2)
        #expect(days[1].isEmpty)
        #expect(days[0].totalCost == Decimal(string: "0.0105"))
    }

    // MARK: - Sessions

    @Test func `should start another session after a long pause and count working time within each`() async throws {
        let start = calendar.startOfDay(for: now).addingTimeInterval(60)
        guard now.timeIntervalSince(start) > 3 * 3600 else { return } // too early in the day to fit three hours
        let formatter = ISO8601DateFormatter()
        func at(_ minutes: Double) -> String { formatter.string(from: start.addingTimeInterval(minutes * 60)) }
        try write([line(at: at(0)), line(at: at(10)), line(at: at(120)), line(at: at(125))])
        let today = await today()
        #expect(today.sessionCount == 2)
        #expect(today.workingTime == 15 * 60)
    }

    @Test func `should count lines added to a log since last time once each`() async throws {
        try write([line(id: "1", at: stamp())])
        let log = log()
        let before = await log.days(last: 1)[0]
        try write([line(id: "1", at: stamp()), line(id: "2", input: 2000, output: 1000, at: stamp())])
        let after = await log.days(last: 1)[0]
        #expect(before.totalTokens == 1500)
        #expect(after.totalTokens == 4500)
    }

    // MARK: - The definition

    @Test func `should read a usage history definition with its defaults, and keep it when written out and read back`() throws {
        let json = #"""
        { "records": { "files": "~/x/*.jsonl", "at": "$.at", "tokens": { "total": "$.n" } },
          "freeWhen": { "localEndpoint": { "file": "~/x.json", "url": ["$.a", ["$.b", "$.c"]] } } }
        """#
        let definition = try JSONDecoder().decode(UsageLog.Definition.self, from: Data(json.utf8))
        #expect(definition.records.format == .jsonLines)
        #expect(definition.records.shapes.map(\.id) == [[]])
        #expect(definition.freeWhen?.localEndpoint?.url == [["$.a"], ["$.b", "$.c"]])
        let again = try JSONDecoder().decode(UsageLog.Definition.self, from: JSONEncoder().encode(definition))
        #expect(again == definition)
    }

    @Test func `should read other apps in a usage history with their label and own records, and no prices`() throws {
        let json = #"""
        { "records": { "files": "~/x/*.jsonl", "at": "$.at", "tokens": { "total": "$.n" } },
          "otherApps": [{ "label": "Desk", "records": { "files": "~/desk.json", "format": "json",
                          "at": { "field": "$.day", "format": "yyyy-MM-dd" }, "tokens": { "total": "$.n" } } }] }
        """#
        let definition = try JSONDecoder().decode(UsageLog.Definition.self, from: Data(json.utf8))
        let app = try #require(definition.otherApps?.first)
        #expect(app.label == "Desk")
        #expect(app.definition.records.shapes.map(\.at) == [.formatted(.init(field: "$.day", format: "yyyy-MM-dd"))])
        #expect(app.definition.prices == nil)
        #expect(app.definition.otherApps == nil)
        #expect(try JSONDecoder().decode(UsageLog.Definition.self, from: JSONEncoder().encode(definition)) == definition)
    }

    @Test func `should keep the login's own usage history unchanged when other apps are added`() {
        let app = UsageLog.OtherApp(label: "Desk", records: UsageLog.Records(files: "~/desk.json", format: .json, at: "$.at"))
        let with = UsageLog.Definition(records: Self.definition.records, prices: Self.definition.prices,
                                       freeWhen: Self.definition.freeWhen, sessionGap: Self.definition.sessionGap, otherApps: [app])
        #expect(log(with).fingerprint == log().fingerprint)
    }

    /// A log that writes a record two ways: a reply's usage under it, a side call's at the top.
    private static let twoShapes = #"""
    { "records": { "files": "~/x/*.jsonl",
                   "shapes": [{ "where": { "path": "$.kind", "equals": "reply" }, "at": "$.at", "tokens": { "total": "$.reply.n" } },
                              { "where": { "path": "$.kind", "equals": "side" }, "at": "$.at", "tokens": { "total": "$.n" } }] } }
    """#

    @Test func `should keep a log's shapes when an added login's patch moves its files`() throws {
        let definition = try JSONDecoder().decode(UsageLog.Definition.self, from: Data(Self.twoShapes.utf8))
        let patch = JSONValue.object(["records": .object(["files": .string("{{account.dir}}/*.jsonl")])])

        let moved = try definition.patched(with: patch).filled(["dir": "/tmp/work"], scope: "account")

        #expect(moved.records.files == "/tmp/work/*.jsonl")
        #expect(moved.records.shapes == definition.records.shapes)
        #expect(moved.records.shapes.count == 2)
    }

    @Test func `should refuse a log that gives a record's fields beside its shapes`() {
        let json = Self.twoShapes.replacingOccurrences(of: #""files": "~/x/*.jsonl","#, with: #""files": "~/x/*.jsonl", "at": "$.at","#)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UsageLog.Definition.self, from: Data(json.utf8)) }
    }

    @Test func `should refuse a shape in a list that has no where`() {
        let json = Self.twoShapes.replacingOccurrences(of: #""where": { "path": "$.kind", "equals": "side" }, "#, with: "")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UsageLog.Definition.self, from: Data(json.utf8)) }
    }

    @Test func `should count an app's daily total on the day it names, with no cost known`() async throws {
        let app = UsageLog.OtherApp(label: "Desk", records: UsageLog.Records(
            files: "~/desk/today.json", format: .json,
            at: .formatted(.init(field: "$.day", format: "yyyy-MM-dd")), tokens: UsageLog.Tokens(total: "$.n")))
        let url = home.appendingPathComponent("desk/today.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = formatter.string(from: calendar.date(byAdding: .day, value: -1, to: now)!)
        try #"{"day":"\#(yesterday)","n":74422}"#.write(to: url, atomically: true, encoding: .utf8)

        let days = await log(app.definition).days(last: 2)

        #expect(days.map(\.totalTokens) == [74422, 0])
        #expect(log(app.definition).knowsCost == false)
    }
}
