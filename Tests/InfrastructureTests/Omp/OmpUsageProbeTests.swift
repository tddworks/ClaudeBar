import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("OmpUsageProbe Tests")
struct OmpUsageProbeTests {

    private static let validOutput = OmpUsageProbeParsingTests.sampleResponse

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when omp binary is found`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn("/Users/dev/.bun/bin/omp")
        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when omp binary is not found`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)
        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Success Tests

    @Test
    func `probe runs omp usage --json and returns snapshot`() async throws {
        let mockExecutor = MockCLIExecutor()

        given(mockExecutor).locate(.any).willReturn("/Users/dev/.bun/bin/omp")
        given(mockExecutor).execute(
            binary: .value("omp"),
            args: .value(["usage", "--json"]),
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: Self.validOutput, exitCode: 0))

        let probe = OmpUsageProbe(cliExecutor: mockExecutor)
        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "omp")
        #expect(snapshot.quotas.count == 7)
        #expect(snapshot.quota(for: .timeLimit("Claude 5h"))?.percentRemaining == 92.0)
    }

    // MARK: - Probe Error Tests

    @Test
    func `probe throws cliNotFound when binary missing`() async {
        let mockExecutor = MockCLIExecutor()
        given(mockExecutor).locate(.any).willReturn(nil)

        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        await #expect(throws: ProbeError.cliNotFound("omp")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on non-zero exit`() async {
        let mockExecutor = MockCLIExecutor()

        given(mockExecutor).locate(.any).willReturn("/Users/dev/.bun/bin/omp")
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: "env: bun: No such file or directory", exitCode: 127))

        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `execution failure never surfaces raw CLI output`() async {
        // Usage output carries account emails/ids; the thrown error reaches
        // the UI via `lastError` and must only name the exit code.
        let mockExecutor = MockCLIExecutor()

        given(mockExecutor).locate(.any).willReturn("/Users/dev/.bun/bin/omp")
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(
            output: "partial { \"email\": \"leak@example.com\", \"accountId\": \"tok-abc123\" } crash",
            exitCode: 3
        ))

        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        // Exact match pins the complete surfaced message (ProbeError's
        // Equatable compares payloads) — no fragment of CLI output survives.
        await #expect(throws: ProbeError.executionFailed("omp usage exited with code 3")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws on unparseable output`() async {
        let mockExecutor = MockCLIExecutor()

        given(mockExecutor).locate(.any).willReturn("/Users/dev/.bun/bin/omp")
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willReturn(CLIResult(output: "Unexpected interactive prompt", exitCode: 0))

        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe wraps executor failures as executionFailed`() async {
        let mockExecutor = MockCLIExecutor()

        given(mockExecutor).locate(.any).willReturn("/Users/dev/.bun/bin/omp")
        given(mockExecutor).execute(
            binary: .any,
            args: .any,
            input: .any,
            timeout: .any,
            workingDirectory: .any,
            autoResponses: .any
        ).willThrow(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process timed out"]))

        let probe = OmpUsageProbe(cliExecutor: mockExecutor)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }
}
