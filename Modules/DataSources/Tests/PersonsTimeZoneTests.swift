import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Mockable
import Quotas
import Testing
@testable import DataSources

/// The day a record counts on, and the zone a mapping script or a request
/// sees, are the person's: their OS's zone through `Platform.timeZone`, never
/// Foundation's `.current`, which is GMT on Windows (#565). Each test fixes
/// the zone at Seoul, so a UTC CI runner catches a regression.
@Suite
struct PersonsTimeZoneTests {
    /// 2026-05-27 16:30 UTC: 01:30 on the 28th in Seoul.
    private static let lateUTC = Date(timeIntervalSince1970: 1_779_899_400)
    /// The 28th's midnight in Seoul: 2026-05-27 15:00 UTC.
    private static let seoulMidnight = Date(timeIntervalSince1970: 1_779_894_000)

    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    @Test func `should count a record on the day it was in the person's zone`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".acme/log.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"at":"2026-05-27T16:30:00Z","tokens":500}"#.utf8).write(to: file)
        let definition = UsageLog.Definition(records: .init(files: "~/.acme/*.jsonl", at: "$.at", tokens: .init(total: "$.tokens")))
        let now = Self.lateUTC.addingTimeInterval(3600)

        let log = DataSources.makeUsageLog(definition, platform: .current(in: Zones.seoul), environment: { _ in nil },
                                           homeDirectory: home, now: { now })
        let days = await log.days(last: 2)

        #expect(log.today == Self.seoulMidnight)
        #expect(days.filter { $0.totalTokens > 0 }.map(\.date) == [Self.seoulMidnight])
    }

    @Test func `should give a mapping script the person's zone, its Date's local time, and read its reset times there`() throws {
        let engine = MockScriptEngine()
        let seen = Seen()
        given(engine).evaluate(.any, after: .any, strings: .any, functions: .any, localTime: .any)
            .willProduce { _, _, strings, functions, localTime in
                seen.input = strings["__input"]
                seen.reset = functions["humanDate"]?("Jan 15, 3:30pm")
                seen.localTime = localTime.identifier
                return #"{"quotas":[]}"#
            }
        let now = Date(timeIntervalSince1970: 1_781_524_800) // 2026-06-15 12:00 UTC
        let mapper = ScriptMapper(file: "acme.js", source: "", engine: engine, zone: Zones.seoul, now: { now })

        _ = try? mapper.read(Response(text: "{}"), facts: MappingFacts(), providerId: "acme")

        let text = try #require(seen.input)
        let input = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect((input["context"] as? [String: Any])?["timeZone"] as? String == "Asia/Seoul")
        #expect(seen.reset == 1_799_994_600) // 2027-01-15 15:30 in Seoul
        #expect(seen.localTime == "Asia/Seoul")
    }

    @Test func `should send the person's zone where a request asks for system.timeZone`() async throws {
        let network = MockNetworkClient()
        let seen = Seen()
        given(network).request(.any).willProduce { request in
            seen.input = request.value(forHTTPHeaderField: "X-Time-Zone")
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let request = HTTPRequest(url: "https://acme.test/usage", headers: ["X-Time-Zone": "{{system.timeZone}}"])

        _ = try await HTTPFetcher(request: request, network: network, zone: Zones.seoul, now: { Self.lateUTC }).fetch(with: nil)

        #expect(seen.input == "Asia/Seoul")
    }
}

private final class Seen: @unchecked Sendable {
    var input: String?
    var reset: Double?
    var localTime: String?
}
