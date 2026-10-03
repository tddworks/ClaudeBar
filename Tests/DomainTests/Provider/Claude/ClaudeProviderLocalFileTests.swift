import Testing
import Foundation
import Mockable
@testable import Domain

/// ClaudeProvider behaviour in Local File mode — the buddy-tokens.json probe
/// for Claude Desktop users without a Claude Code CLI (issue #198).
@Suite("ClaudeProvider Local File Mode Tests")
@MainActor
struct ClaudeProviderLocalFileTests {

    // MARK: - Probe Selection

    @Test
    func `refresh in localFile mode uses the file probe`() async throws {
        let settings = FakeLocalFileSettings(probeMode: .localFile)
        let fileProbe = MockUsageProbe()
        let fileSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            extensionMetrics: [ExtensionMetric(label: "Tokens Today", value: "74,422", unit: "tokens")]
        )
        given(fileProbe).probe().willReturn(fileSnapshot)

        let claude = ClaudeProvider(
            cliProbe: unusedProbe(),
            apiProbe: unusedProbe(),
            fileProbe: fileProbe,
            settingsRepository: settings
        )

        let snapshot = try await claude.refresh()
        #expect(snapshot.extensionMetrics?.first?.label == "Tokens Today")
        #expect(snapshot.extensionMetrics?.first?.value == "74,422")
    }

    @Test
    func `localFile mode without a file probe falls back to the CLI probe`() async throws {
        // The legacy two-probe init carries no file probe; localFile mode must
        // still work by falling back to the CLI rather than crashing.
        let settings = FakeLocalFileSettings(probeMode: .localFile)
        let cliSnapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 64, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        )
        let cliProbe = MockUsageProbe()
        given(cliProbe).probe().willReturn(cliSnapshot)

        let claude = ClaudeProvider(
            cliProbe: cliProbe,
            apiProbe: unusedProbe(),
            settingsRepository: settings
        )

        let snapshot = try await claude.refresh()
        #expect(snapshot.quotas.first?.percentRemaining == 64)
    }

    // MARK: - No Cross-Fallback

    @Test
    func `localFile mode does not fall back to CLI when the file probe fails`() async throws {
        // File mode reports a different metric (daily tokens) than CLI/API
        // (five-hour windows). Silently substituting CLI data would show the
        // wrong semantic, so a failing file probe surfaces its error instead
        // of swapping probes.
        let settings = FakeLocalFileSettings(probeMode: .localFile)
        let fileProbe = MockUsageProbe()
        given(fileProbe).probe().willThrow(ProbeError.noData)

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)
        given(cliProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 90, quotaType: .session, providerId: "claude")],
            capturedAt: Date()
        ))

        let claude = ClaudeProvider(
            cliProbe: cliProbe,
            apiProbe: unusedProbe(),
            fileProbe: fileProbe,
            settingsRepository: settings
        )

        do {
            _ = try await claude.refresh()
            Issue.record("Expected refresh to throw")
        } catch ProbeError.noData {
            // Expected — the file probe's error, not CLI data
        } catch {
            Issue.record("Expected ProbeError.noData, got \(error)")
        }
        #expect(claude.snapshot == nil)
    }

    // MARK: - Availability

    @Test
    func `isAvailable in localFile mode reflects the file probe`() async {
        let settings = FakeLocalFileSettings(probeMode: .localFile)
        let fileProbe = MockUsageProbe()
        given(fileProbe).isAvailable().willReturn(true)

        let claude = ClaudeProvider(
            cliProbe: unusedProbe(),
            apiProbe: unusedProbe(),
            fileProbe: fileProbe,
            settingsRepository: settings
        )

        #expect(await claude.isAvailable() == true)
    }

    @Test
    func `isAvailable in localFile mode is false when the file probe is unavailable`() async {
        // A missing buddy-tokens.json must read as "unavailable" in file mode
        // even when the CLI is installed — the user chose file mode because
        // CLI/API data does not apply to their setup.
        let settings = FakeLocalFileSettings(probeMode: .localFile)
        let fileProbe = MockUsageProbe()
        given(fileProbe).isAvailable().willReturn(false)

        let cliProbe = MockUsageProbe()
        given(cliProbe).isAvailable().willReturn(true)

        let claude = ClaudeProvider(
            cliProbe: cliProbe,
            apiProbe: unusedProbe(),
            fileProbe: fileProbe,
            settingsRepository: settings
        )

        #expect(await claude.isAvailable() == false)
    }

    // MARK: - Background Refresh Floor

    @Test
    func `background refresh floor is nil in localFile mode`() {
        // Reading a small local file is cheap; the user's interval stands.
        let settings = FakeLocalFileSettings(probeMode: .localFile)
        let claude = ClaudeProvider(
            cliProbe: unusedProbe(),
            apiProbe: unusedProbe(),
            fileProbe: MockUsageProbe(),
            settingsRepository: settings
        )

        #expect(claude.backgroundRefreshFloor == nil)
    }

    // MARK: - Helpers

    /// A probe whose stubs are never consulted in the scenarios below; if it
    /// were invoked, Chicago-style state assertions would fail instead.
    private func unusedProbe() -> MockUsageProbe {
        let probe = MockUsageProbe()
        given(probe).probe().willThrow(ProbeError.executionFailed("unused probe must not be called"))
        given(probe).isAvailable().willReturn(false)
        return probe
    }
}

/// ClaudeSettingsRepository fake with a configurable probe mode.
private final class FakeLocalFileSettings: ClaudeSettingsRepository, @unchecked Sendable {
    var probeMode: ClaudeProbeMode
    var cliFallbackEnabled: Bool = true

    init(probeMode: ClaudeProbeMode) {
        self.probeMode = probeMode
    }

    func isEnabled(forProvider id: String) -> Bool { true }
    func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool { true }
    func setEnabled(_ enabled: Bool, forProvider id: String) {}
    func customCardURL(forProvider id: String) -> String? { nil }
    func setCustomCardURL(_ url: String?, forProvider id: String) {}
    func claudeProbeMode() -> ClaudeProbeMode { probeMode }
    func setClaudeProbeMode(_ mode: ClaudeProbeMode) { probeMode = mode }
    func claudeCliFallbackEnabled() -> Bool { cliFallbackEnabled }
    func setClaudeCliFallbackEnabled(_ enabled: Bool) { cliFallbackEnabled = enabled }
}
