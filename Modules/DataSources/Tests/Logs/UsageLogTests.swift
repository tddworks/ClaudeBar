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

    @Test func `every day of the range is present, a day with nothing empty`() async throws {
        try write([line(at: stamp())])
        let days = await log().days(last: 3)
        #expect(days.count == 3)
        #expect(days.map(\.date) == DateRange.last(3, endingOn: now).days())
        #expect(days[0].isEmpty && days[1].isEmpty)
        #expect(days[2].totalTokens == 1500)
    }

    @Test func `a record counts on the day its own time falls in`() async throws {
        try write([line(at: stamp()), line(input: 2000, output: 1000, at: stamp(daysAgo: 1))])
        let days = await log().days(last: 2)
        #expect(days[1].totalTokens == 1500)
        #expect(days[0].totalTokens == 3000)
    }

    @Test func `nothing logged is every day empty`() async {
        #expect(await log().days(last: 2).allSatisfy(\.isEmpty))
    }

    @Test func `the glob reaches any depth and only matching files`() async throws {
        try write([line(at: stamp())], to: "a/b/c/deep.jsonl")
        try write([line(at: stamp())], to: "notes.txt")
        #expect(await today().totalTokens == 1500)
    }

    // MARK: - Written twice, counted once

    @Test func `a record written twice counts once`() async throws {
        let copy = line(id: "1", at: stamp())
        try write([copy, copy, copy])
        #expect(await today().totalTokens == 1500)
    }

    @Test func `the last copy of a record wins`() async throws {
        try write([line(id: "1", output: 1, at: stamp()), line(id: "1", output: 1, at: stamp(0.1)), line(id: "1", output: 500, at: stamp(0.9))])
        let today = await today()
        #expect(today.outputTokens == 500)
        #expect(today.totalTokens == 1500)
    }

    @Test func `a record copied into another file counts once`() async throws {
        try write([line(id: "1", at: stamp())], to: "p/one.jsonl")
        try write([line(id: "1", at: stamp())], to: "p/two.jsonl")
        #expect(await today().totalTokens == 1500)
    }

    @Test func `records with different identities, or none, all count`() async throws {
        try write([line(id: "1", at: stamp()), line(id: "2", input: 2000, output: 1000, at: stamp()),
                   line(at: stamp()), line(at: stamp())])
        #expect(await today().totalTokens == 7500)
    }

    // MARK: - Prices

    @Test func `cost and cache savings come from the price list`() async throws {
        try write([line(input: 1000, output: 500, cacheRead: 1_000_000, at: stamp())])
        let today = await today()
        #expect(today.cacheReadTokens == 1_000_000)
        #expect(today.cachedSavings == Decimal(string: "2.7"))
        #expect(today.totalCost == Decimal(string: "0.3105"))
    }

    @Test func `the log's own cost wins over any price`() async throws {
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

    @Test func `on a local route an unpriced model costs nothing today`() async throws {
        try route("http://localhost:11434")
        try write([line(model: "acme-internal-7b", at: stamp())])
        #expect(await today().totalCost == 0)
    }

    @Test func `on a remote route an unpriced model keeps its estimate`() async throws {
        try route("https://gateway.example.com")
        try write([line(model: "acme-internal-7b", at: stamp())])
        #expect(await today().totalCost == Decimal(string: "0.0105"))
    }

    @Test func `the route now never zeroes an earlier day`() async throws {
        try route("http://localhost:11434")
        try write([line(model: "acme-internal-7b", at: stamp(daysAgo: 1))])
        let days = await log().days(last: 2)
        #expect(days[1].isEmpty)
        #expect(days[0].totalCost == Decimal(string: "0.0105"))
    }

    // MARK: - Sessions

    @Test func `a long pause starts another session; working time spans each`() async throws {
        let start = calendar.startOfDay(for: now).addingTimeInterval(60)
        guard now.timeIntervalSince(start) > 3 * 3600 else { return } // too early in the day to fit three hours
        let formatter = ISO8601DateFormatter()
        func at(_ minutes: Double) -> String { formatter.string(from: start.addingTimeInterval(minutes * 60)) }
        try write([line(at: at(0)), line(at: at(10)), line(at: at(120)), line(at: at(125))])
        let today = await today()
        #expect(today.sessionCount == 2)
        #expect(today.workingTime == 15 * 60)
    }

    @Test func `lines appended between reads count once`() async throws {
        try write([line(id: "1", at: stamp())])
        let log = log()
        let before = await log.days(last: 1)[0]
        try write([line(id: "1", at: stamp()), line(id: "2", input: 2000, output: 1000, at: stamp())])
        let after = await log.days(last: 1)[0]
        #expect(before.totalTokens == 1500)
        #expect(after.totalTokens == 4500)
    }

    // MARK: - The definition

    @Test func `a usageHistory block decodes, a single url as a one-path entry`() throws {
        let json = #"""
        { "records": { "files": "~/x/*.jsonl", "at": "$.at", "tokens": { "total": "$.n" } },
          "freeWhen": { "localEndpoint": { "file": "~/x.json", "url": ["$.a", ["$.b", "$.c"]] } } }
        """#
        let definition = try JSONDecoder().decode(UsageLog.Definition.self, from: Data(json.utf8))
        #expect(definition.records.format == .jsonLines)
        #expect(definition.records.id.isEmpty)
        #expect(definition.freeWhen?.localEndpoint?.url == [["$.a"], ["$.b", "$.c"]])
        let again = try JSONDecoder().decode(UsageLog.Definition.self, from: JSONEncoder().encode(definition))
        #expect(again == definition)
    }
}
