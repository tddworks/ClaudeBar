import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite("OpenCodeAPIUsageProbe Parsing Tests")
struct OpenCodeAPIUsageProbeParsingTests {

    /// Shape returned by `GET https://opencode.ai/zen/go/v1/usage`
    /// (anomalyco/opencode#16513). `percent` is *used*, `resetsAt` is absolute.
    static let usageJSON = Data("""
    {
      "usage": {
        "rolling": { "status": "ok", "percent": 1, "resetsAt": "2026-08-24T15:34:00.000Z" },
        "weekly":  { "status": "ok", "percent": 17, "resetsAt": "2026-08-29T00:00:00.000Z" },
        "monthly": { "status": "rate-limited", "percent": 100, "resetsAt": "2026-09-21T13:00:00.000Z" }
      }
    }
    """.utf8)

    @Test
    func `parses three quotas mapping used percent to remaining`() throws {
        let snapshot = try OpenCodeAPIUsageProbe.parseResponse(Self.usageJSON)

        #expect(snapshot.providerId == "opencode-go")
        #expect(snapshot.quotas.count == 3)

        let session = try #require(snapshot.quotas.first { $0.quotaType == .session })
        #expect(session.percentRemaining == 99)

        let weekly = try #require(snapshot.quotas.first { $0.quotaType == .weekly })
        #expect(weekly.percentRemaining == 83)

        let monthly = try #require(snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") })
        #expect(monthly.percentRemaining == 0)
        #expect(monthly.isDepleted)
    }

    @Test
    func `uses server-provided reset timestamps`() throws {
        let snapshot = try OpenCodeAPIUsageProbe.parseResponse(Self.usageJSON)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let session = try #require(snapshot.quotas.first { $0.quotaType == .session })
        #expect(session.resetsAt == formatter.date(from: "2026-08-24T15:34:00.000Z"))

        let weekly = try #require(snapshot.quotas.first { $0.quotaType == .weekly })
        #expect(weekly.resetsAt == formatter.date(from: "2026-08-29T00:00:00.000Z"))
    }

    @Test
    func `sets window durations so the UI can draw progress markers`() throws {
        let snapshot = try OpenCodeAPIUsageProbe.parseResponse(Self.usageJSON)

        let session = try #require(snapshot.quotas.first { $0.quotaType == .session })
        #expect(session.windowDuration == TimeInterval(5 * 3600))

        let weekly = try #require(snapshot.quotas.first { $0.quotaType == .weekly })
        #expect(weekly.windowDuration == TimeInterval(7 * 86400))
    }

    @Test
    func `rate-limited status clamps remaining to zero even when percent is below 100`() throws {
        let json = Data("""
        {"usage":{"rolling":{"status":"rate-limited","percent":98,"resetsAt":"2026-08-24T15:34:00.000Z"}}}
        """.utf8)

        let snapshot = try OpenCodeAPIUsageProbe.parseResponse(json)

        let session = try #require(snapshot.quotas.first { $0.quotaType == .session })
        #expect(session.percentRemaining == 0)
    }

    @Test
    func `clamps over-100 usage to zero remaining`() throws {
        let json = Data("""
        {"usage":{"weekly":{"status":"ok","percent":130,"resetsAt":"2026-08-29T00:00:00.000Z"}}}
        """.utf8)

        let snapshot = try OpenCodeAPIUsageProbe.parseResponse(json)

        #expect(snapshot.quotas.first?.percentRemaining == 0)
    }

    @Test
    func `tolerates missing windows and fractional percents`() throws {
        let json = Data("""
        {"usage":{"rolling":{"status":"ok","percent":12.5,"resetsAt":"2026-08-24T15:34:00Z"}}}
        """.utf8)

        let snapshot = try OpenCodeAPIUsageProbe.parseResponse(json)

        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 87.5)
        #expect(snapshot.quotas.first?.resetsAt != nil)
    }

    @Test
    func `throws parseFailed when usage object is missing`() {
        let json = Data(#"{"type":"error","error":{"type":"AuthError","message":"Unauthorized"}}"#.utf8)

        #expect(throws: ProbeError.self) {
            try OpenCodeAPIUsageProbe.parseResponse(json)
        }
    }

    @Test
    func `throws parseFailed when no windows could be parsed`() {
        let json = Data(#"{"usage":{}}"#.utf8)

        #expect(throws: ProbeError.parseFailed("No usage windows in response")) {
            try OpenCodeAPIUsageProbe.parseResponse(json)
        }
    }

    @Test
    func `throws parseFailed on invalid JSON`() {
        #expect(throws: ProbeError.self) {
            try OpenCodeAPIUsageProbe.parseResponse(Data("<html>".utf8))
        }
    }
}
