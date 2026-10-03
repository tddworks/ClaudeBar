import Foundation
import Testing
import Domain
@testable import Infrastructure

@Suite
struct ClaudeDesktopFileUsageProbeTests {
    /// Writes a buddy-tokens.json fixture into a temp Claude dir and returns
    /// the directory. Tests never touch the real ~/Library path.
    private func makeTempClaudeDir(with fileContents: String?) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Claude")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        if let fileContents {
            try fileContents.write(
                to: tmpDir.appendingPathComponent("buddy-tokens.json"),
                atomically: true,
                encoding: .utf8
            )
        }
        return tmpDir
    }

    /// A calendar pinned to GMT+5 so "local day" differs from the UTC day for
    /// half of every UTC day. `now` is a fixed instant in that zone.
    private func gmtPlus5Calendar(now: Date) -> (Calendar, @Sendable () -> Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600)!
        return (calendar, { now })
    }

    /// 2026-05-28 00:00 UTC == 2026-05-28 05:00 in GMT+5 — the local day is
    /// the 28th.
    private static let lateEveningUTC = Date(timeIntervalSince1970: 1_779_926_400)

    private func makeProbe(dir: URL, now: Date = ClaudeDesktopFileUsageProbeTests.lateEveningUTC) -> ClaudeDesktopFileUsageProbe {
        let (calendar, clock) = gmtPlus5Calendar(now: now)
        return ClaudeDesktopFileUsageProbe(claudeDir: dir, calendar: calendar, now: clock)
    }

    // MARK: - Current file (happy path)

    @Test
    func `reads today's tokens from a current buddy-tokens file`() async throws {
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-28", "tokens": 74422}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.isEmpty)
        let metric = try #require(snapshot.extensionMetrics?.first)
        #expect(metric.label == "Tokens Today")
        #expect(metric.unit == "tokens")
        #expect(metric.value == "74,422")
    }

    @Test
    func `current file is available`() async throws {
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-28", "tokens": 100}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `snapshot capturedAt uses the injected clock`() async throws {
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-28", "tokens": 100}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let snapshot = try await probe.probe()

        #expect(snapshot.capturedAt == ClaudeDesktopFileUsageProbeTests.lateEveningUTC)
    }

    // MARK: - Missing file

    @Test
    func `missing file throws noData`() async throws {
        let dir = try makeTempClaudeDir(with: nil)
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        #expect(await probe.isAvailable() == false)
        await #expect(throws: ProbeError.noData) {
            try await probe.probe()
        }
    }

    // MARK: - Malformed file

    @Test
    func `malformed JSON throws parseFailed`() async throws {
        let dir = try makeTempClaudeDir(with: #"{"tokens-today": {"date":"2026-05-28""#)
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.parseFailed("buddy-tokens.json is not valid JSON")) {
            try await probe.probe()
        }
    }

    // MARK: - Schema changes (fail gracefully)

    @Test
    func `missing tokens-today key throws parseFailed`() async throws {
        let dir = try makeTempClaudeDir(with: #"{"something-else": {}}"#)
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today'")) {
            try await probe.probe()
        }
    }

    @Test
    func `missing tokens value throws parseFailed`() async throws {
        let dir = try makeTempClaudeDir(with: #"{"tokens-today": {"date": "2026-05-28"}}"#)
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today.tokens'")) {
            try await probe.probe()
        }
    }

    @Test
    func `missing date value throws parseFailed`() async throws {
        let dir = try makeTempClaudeDir(with: #"{"tokens-today": {"tokens": 100}}"#)
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.parseFailed("buddy-tokens.json schema changed: missing 'tokens-today.date'")) {
            try await probe.probe()
        }
    }

    @Test
    func `negative token count throws parseFailed`() async throws {
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-28", "tokens": -5}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.parseFailed("buddy-tokens.json schema changed: invalid 'tokens' value")) {
            try await probe.probe()
        }
    }

    // MARK: - Date validation against the user's local day

    @Test
    func `stale date never shows as today's usage`() async throws {
        // Local day (GMT+5) is 2026-05-28; the file still holds the 27th.
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-27", "tokens": 74422}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.noData) {
            try await probe.probe()
        }
    }

    @Test
    func `future date never shows as today's usage`() async throws {
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-29", "tokens": 100}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.noData) {
            try await probe.probe()
        }
    }

    @Test
    func `unparseable date throws parseFailed`() async throws {
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "May 28 2026", "tokens": 100}}"#
        )
        let probe = makeProbe(dir: dir)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        await #expect(throws: ProbeError.parseFailed("buddy-tokens.json schema changed: invalid 'date' value")) {
            try await probe.probe()
        }
    }

    @Test
    func `date matching the local calendar day is current`() async throws {
        // 2026-05-27 23:06 UTC == 2026-05-28 04:06 in GMT+5. A file stamped
        // "2026-05-28" (the user's local day, not the UTC day) is current.
        let now = Date(timeIntervalSince1970: 1_779_923_200)
        let dir = try makeTempClaudeDir(
            with: #"{"tokens-today": {"date": "2026-05-28", "tokens": 42}}"#
        )
        let probe = makeProbe(dir: dir, now: now)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let snapshot = try await probe.probe()
        #expect(snapshot.extensionMetrics?.first?.value == "42")
    }
}
