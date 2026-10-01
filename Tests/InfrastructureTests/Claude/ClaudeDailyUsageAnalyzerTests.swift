import Foundation
import Testing
import Domain
@testable import Infrastructure

@Suite
struct ClaudeDailyUsageAnalyzerTests {
    /// Creates a temp directory with JSONL files for testing.
    private func setupTempClaudeDir(with jsonlContent: String, fileName: String = "test-session.jsonl") throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectsDir = tmpDir.appendingPathComponent("projects").appendingPathComponent("test-project")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        let fileURL = projectsDir.appendingPathComponent(fileName)
        try jsonlContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return tmpDir
    }

    /// Creates a temp directory with multiple named JSONL files (for cross-file dedup tests).
    private func setupTempClaudeDir(files: [String: String]) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let projectsDir = tmpDir.appendingPathComponent("projects").appendingPathComponent("test-project")
        try FileManager.default.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: projectsDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return tmpDir
    }

    private static func todayTimestamp(_ offsetSeconds: TimeInterval = 0) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(offsetSeconds))
    }

    @Test func `analyzes today's usage from JSONL files`() async throws {
        let todayStr = ISO8601DateFormatter().string(from: Date())
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(todayStr)"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let analyzer = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir)
        let report = try await analyzer.analyzeToday()

        #expect(report.today.totalTokens == 1500)
        #expect(report.today.totalCost > 0)
    }

    @Test func `previous day is empty when no data exists`() async throws {
        let todayStr = ISO8601DateFormatter().string(from: Date())
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50}},"timestamp":"\(todayStr)"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let analyzer = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir)
        let report = try await analyzer.analyzeToday()

        #expect(report.previous.isEmpty)
        #expect(report.previous.totalTokens == 0)
    }

    @Test func `produces empty report when no files exist`() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let analyzer = ClaudeDailyUsageAnalyzer(claudeDir: tmpDir)
        let report = try await analyzer.analyzeToday()

        #expect(report.today.isEmpty)
        #expect(report.previous.isEmpty)
    }

    @Test func `aggregates cache tokens and savings`() async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let todayStr = formatter.string(from: Date())
        // Sonnet pricing: input $3/M, cache_read $0.30/M → savings = 1M * $2.70 = $2.70
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":2000,"cache_read_input_tokens":1000000}},"timestamp":"\(todayStr)"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let analyzer = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir)
        let report = try await analyzer.analyzeToday()

        #expect(report.today.inputTokens == 1000)
        #expect(report.today.outputTokens == 500)
        #expect(report.today.cacheCreationTokens == 2000)
        #expect(report.today.cacheReadTokens == 1_000_000)
        #expect(report.today.cachedSavings == Decimal(string: "2.7"))
        // hit rate = 1M / (1M + 1000) ≈ 0.999
        #expect(report.today.cacheHitRate > 0.99)
    }

    @Test func `counts byte-identical duplicate lines once`() async throws {
        let ts = Self.todayTimestamp()
        // Same message.id + requestId repeated 3× with identical usage (parallel tool calls).
        let line = #"{"type":"assistant","requestId":"req_1","message":{"id":"msg_A","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\#(ts)"}"#
        let jsonl = "\(line)\n\(line)\n\(line)"
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir).analyzeToday()
        // Counted once, not 3×.
        #expect(report.today.totalTokens == 1500)
    }

    @Test func `keeps final streaming snapshot output tokens`() async throws {
        let t1 = Self.todayTimestamp(0)
        let t2 = Self.todayTimestamp(0.1)
        let t3 = Self.todayTimestamp(0.9)
        // Streaming: same (id, req); output_tokens grows 1 → 1 → 500. Final wins.
        let jsonl = """
        {"type":"assistant","requestId":"req_1","message":{"id":"msg_A","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":1}},"timestamp":"\(t1)"}
        {"type":"assistant","requestId":"req_1","message":{"id":"msg_A","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":1}},"timestamp":"\(t2)"}
        {"type":"assistant","requestId":"req_1","message":{"id":"msg_A","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(t3)"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir).analyzeToday()
        #expect(report.today.outputTokens == 500)
        #expect(report.today.totalTokens == 1500)
    }

    @Test func `deduplicates same response copied across session files`() async throws {
        let ts = Self.todayTimestamp()
        // Identical (id, req) appearing in two different session files (resume/branch copy).
        let line = #"{"type":"assistant","requestId":"req_1","message":{"id":"msg_A","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\#(ts)"}"#
        let claudeDir = try setupTempClaudeDir(files: [
            "session-1.jsonl": line,
            "session-2.jsonl": line
        ])
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir).analyzeToday()
        #expect(report.today.totalTokens == 1500)
    }

    @Test func `keeps distinct responses with different ids`() async throws {
        let ts = Self.todayTimestamp()
        let jsonl = """
        {"type":"assistant","requestId":"req_1","message":{"id":"msg_A","model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(ts)"}
        {"type":"assistant","requestId":"req_2","message":{"id":"msg_B","model":"claude-sonnet-4-6","usage":{"input_tokens":2000,"output_tokens":1000}},"timestamp":"\(ts)"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir).analyzeToday()
        #expect(report.today.totalTokens == 4500)
    }

    @Test func `counts records missing identity keys as-is`() async throws {
        let ts = Self.todayTimestamp()
        // No requestId / no message.id — must NOT be merged together.
        let line = #"{"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\#(ts)"}"#
        let jsonl = "\(line)\n\(line)"
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir).analyzeToday()
        // Both kept (can't prove they're duplicates without keys).
        #expect(report.today.totalTokens == 3000)
    }

    @Test func `costs nothing for a recognised open weight family name`() async throws {
        // issue #190 rule 2: the name alone says "open weight", so the cost is $0 with
        // no provenance involved. Cache tokens are in the fixture on purpose — savings
        // is 0 only because the free price is applied, not because nothing was cached.
        let jsonl = """
        {"type":"assistant","message":{"model":"qwen3-coder:30b","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":1000000}},"timestamp":"\(Self.todayTimestamp())"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir).analyzeToday()

        #expect(report.today.totalCost == 0)
        #expect(report.today.cachedSavings == 0)
        // The cache read really happened, it was just not billed.
        #expect(report.today.cacheReadTokens == 1_000_000)
        // Tokens were still consumed — the token card keeps counting them.
        #expect(report.today.totalTokens == 1500)
    }

    @Test func `costs nothing for a private fine tune served locally`() async throws {
        // issue #190 rule 3: a name the family list has never heard of. Provenance is
        // the only thing that can price this, and cache savings must follow it.
        let jsonl = """
        {"type":"assistant","message":{"model":"acme-internal-7b","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":1000000}},"timestamp":"\(Self.todayTimestamp())"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let local = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir, isLocallyServed: { true })
        let remote = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir, isLocallyServed: { false })

        let localReport = try await local.analyzeToday()
        let remoteReport = try await remote.analyzeToday()

        #expect(localReport.today.totalCost == 0)
        #expect(localReport.today.cachedSavings == 0)
        // Same session, remote endpoint: nothing proves it was free.
        #expect(remoteReport.today.totalCost > 0)
        #expect(remoteReport.today.cachedSavings > 0)
    }

    @Test func `costs nothing for an unpriced model on a locally routed session`() async throws {
        // The same name on a remote endpoint may still be billed, so it keeps its
        // Sonnet-rate estimate there.
        let jsonl = """
        {"type":"assistant","message":{"model":"some-unknown-model","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(Self.todayTimestamp())"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let local = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir, isLocallyServed: { true })
        let remote = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir, isLocallyServed: { false })

        let localReport = try await local.analyzeToday()
        let remoteReport = try await remote.analyzeToday()

        #expect(localReport.today.totalCost == 0)
        // Sonnet estimate for 1K input + 500 output tokens.
        #expect(remoteReport.today.totalCost == Decimal(string: "0.0105"))
        #expect(localReport.today.totalTokens == remoteReport.today.totalTokens)
    }

    @Test func `prices a known anthropic model at list price`() async throws {
        // Regression guard: real spend must keep being counted — even with a loopback
        // endpoint configured, which must not retroactively zero the 2-day window.
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(Self.todayTimestamp())"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let analyzer = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir, isLocallyServed: { true })
        let report = try await analyzer.analyzeToday()

        #expect(report.today.totalCost == Decimal(string: "0.0105"))
    }

    @Test func `yesterday keeps its estimate when a loopback route is configured`() async throws {
        // `servedLocally` describes the route as it is *now*, so it must not reach back
        // a day and zero an unpriced name recorded before the switch — the same
        // retroactive erasure rule 1 guards against for priced models.
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())
        )!.addingTimeInterval(3600 * 12)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let jsonl = """
        {"type":"assistant","message":{"model":"some-unknown-model","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(formatter.string(from: yesterday))"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let report = try await ClaudeDailyUsageAnalyzer(claudeDir: claudeDir, isLocallyServed: { true })
            .analyzeToday()

        #expect(report.today.isEmpty)
        // Sonnet estimate preserved rather than zeroed.
        #expect(report.previous.totalCost == Decimal(string: "0.0105"))
        #expect(report.previous.totalTokens == 1500)
    }

    @Test func `separates today and yesterday records`() async throws {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))!.addingTimeInterval(3600 * 12)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let todayStr = formatter.string(from: now)
        let yesterdayStr = formatter.string(from: yesterday)

        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"\(todayStr)"}
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":2000,"output_tokens":1000}},"timestamp":"\(yesterdayStr)"}
        """
        let claudeDir = try setupTempClaudeDir(with: jsonl)
        defer { try? FileManager.default.removeItem(at: claudeDir) }

        let analyzer = ClaudeDailyUsageAnalyzer(claudeDir: claudeDir)
        let report = try await analyzer.analyzeToday()

        #expect(report.today.totalTokens == 1500)
        #expect(report.previous.totalTokens == 3000)
    }
}
