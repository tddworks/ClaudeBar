import Foundation
import Quotas
import Testing
@testable import DataSources

/// A mapping script's `Date` is on the person's clock, the zone the platform's
/// `TimeZone` port gives (#567), never the OS's, so plain JavaScript reads the
/// same on every machine (#570). Los Angeles, fixed, moves its clocks on
/// 2026-03-08, so a day that morning is 23 hours on any machine.
@Suite
struct ScriptCalendarTests {
    private func read(script: String) throws -> UsageQuota {
        let definition = DataSourceDefinition(kind: "api", fetch: .http(HTTPRequest(url: "https://acme.test")),
                                              mapping: .script(ScriptMapping(file: "days.js")))
        let source = DataSources.make(definition, providerId: "acme",
                                      platform: .current(in: Zones.fixed("America/Los_Angeles")),
                                      network: MockNetworkClient(), scripts: { _ in script }, environment: { _ in nil },
                                      homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        return try #require(try source.read(Response(text: "{}")).quotas.first)
    }

    @Test func `should count a day across a daylight-saving change in the person's zone`() throws {
        let quota = try read(script: """
        function read() {
          const saturday = new Date(2026, 2, 7) / 1000, monday = new Date(2026, 2, 9) / 1000;
          return { quotas: [{ type: 'time', name: 'Weekend', percentRemaining: 50,
                              resetsAt: monday, windowSeconds: monday - saturday }] };
        }
        """)
        // Monday 00:00 PDT is 07:00 UTC; Saturday 00:00 PST was 08:00 UTC.
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1_773_039_600))
        #expect(quota.windowDuration == TimeInterval(47 * 3600))
    }

    @Test func `should read an instant's date and time in the person's zone`() throws {
        let quota = try read(script: """
        function read() {
          const d = new Date((1773039600 - 1) * 1000);
          return { quotas: [{ type: 'time', name: 'Day', percentRemaining: 50,
                              resetText: [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds()].join(' ') }] };
        }
        """)
        #expect(quota.resetText == "2026 3 8 23 59 59")
    }

    @Test func `should carry a month that runs past the year`() throws {
        let quota = try read(script: """
        function read() {
          return { quotas: [{ type: 'time', name: 'Year', percentRemaining: 50, resetsAt: new Date(2026, 12, 1, 9, 30) / 1000 }] };
        }
        """)
        // 2027-01-01 09:30 PST.
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 1_798_824_600))
    }

    /// 02:30 on 2026-03-08 doesn't exist and moves forward to 03:30 PDT;
    /// 01:30 on 2026-11-01 happens twice and is the first, PDT.
    @Test(arguments: [
        ("2026, 2, 8, 2, 30", 1_772_965_800.0),
        ("2026, 10, 1, 1, 30", 1_793_521_800),
    ])
    func `should read a clock time the zone skips or repeats as JavaScript does`(_ time: String, _ seconds: Double) throws {
        let quota = try read(script: """
        function read() {
          return { quotas: [{ type: 'time', name: 'Change', percentRemaining: 50, resetsAt: new Date(\(time)) / 1000 }] };
        }
        """)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: seconds))
    }
}
