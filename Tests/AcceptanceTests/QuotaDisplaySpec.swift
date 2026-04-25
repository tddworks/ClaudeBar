import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Quota Display
///
/// Users see quota cards with percentages, progress bars, status badges,
/// and reset times after a provider refresh.
///
/// Behaviors covered:
/// - #8: User sees account info card (email, tier badge, freshness)
/// - #9: User sees quota cards with percentage, progress bar, reset time
/// - #10: User toggles "Remaining" vs "Used" display mode
/// - #13: Unavailable provider shows error message with guidance
/// - #14: Over-quota displays negative percentages
@Suite("Feature: Quota Display")
struct QuotaDisplaySpec {

    private struct TestClock: Clock {
        func sleep(for duration: TimeInterval) async throws {}
    }

    // MARK: - #8: Account info card

    @Suite("Scenario: Account info displays after refresh")
    struct AccountInfo {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `account email and tier are displayed after refresh`() async throws {
            // Given — CLI returns output with account metadata
            let mockExecutor = MockCLIExecutor()
            given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
            given(mockExecutor).execute(
                binary: .any, args: .any, input: .any,
                timeout: .any, workingDirectory: .any, autoResponses: .any
            ).willReturn(CLIResult(output: """
                Claude Code v1.0.27

                Current session
                ████████████████░░░░ 65% left
                Resets in 2h 15m

                Account: user@example.com
                Organization: Acme Corp
                Login method: Claude Max
                """, exitCode: 0))

            let mockResolver = MockAccountInfoResolving()
            given(mockResolver).resolve().willReturn(Domain.AccountInfo(email: "user@example.com", organization: "Acme Corp"))

            let probe = ClaudeUsageProbe(cliExecutor: mockExecutor, accountInfoResolver: mockResolver)
            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — user opens menu and quota is refreshed
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot != nil)
            #expect(claude.snapshot?.accountEmail == "user@example.com")
            #expect(claude.snapshot?.accountTier == .claudeMax)
        }
    }

    // MARK: - #9: Quota cards with percentage, status, reset time

    @Suite("Scenario: Quota cards display correctly after refresh")
    struct QuotaCards {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `healthy session and warning weekly quotas display with correct status`() async throws {
            // Given — CLI returns 65% session (healthy) and 35% weekly (warning)
            let mockExecutor = MockCLIExecutor()
            given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
            given(mockExecutor).execute(
                binary: .any, args: .any, input: .any,
                timeout: .any, workingDirectory: .any, autoResponses: .any
            ).willReturn(CLIResult(output: """
                Current session
                ████████████████░░░░ 65% left
                Resets in 2h 15m

                Current week (all models)
                ██████████░░░░░░░░░░ 35% left
                Resets Jan 15, 3:30pm

                Account: user@example.com
                Login method: Claude Max
                """, exitCode: 0))

            let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)
            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — multiple quota cards with correct statuses
            let snapshot = claude.snapshot
            #expect(snapshot != nil)
            #expect(snapshot!.quotas.count == 2)

            let session = snapshot?.quota(for: .session)
            #expect(session?.percentRemaining == 65)
            #expect(session?.status == .healthy)

            let weekly = snapshot?.quota(for: .weekly)
            #expect(weekly?.percentRemaining == 35)
            #expect(weekly?.status == .warning)
        }

        @Test
        func `exhausted session shows depleted status`() async throws {
            // Given — 0% left
            let mockExecutor = MockCLIExecutor()
            given(mockExecutor).locate(.any).willReturn("/usr/local/bin/claude")
            given(mockExecutor).execute(
                binary: .any, args: .any, input: .any,
                timeout: .any, workingDirectory: .any, autoResponses: .any
            ).willReturn(CLIResult(output: """
                Current session
                ░░░░░░░░░░░░░░░░░░░░ 0% left
                Resets in 30m
                """, exitCode: 0))

            let probe = ClaudeUsageProbe(cliExecutor: mockExecutor)
            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then
            let session = claude.snapshot?.quota(for: .session)
            #expect(session?.percentRemaining == 0)
            #expect(session?.status == .depleted)
        }
    }

    // MARK: - #10: Remaining vs Used display mode

    @Suite("Scenario: Toggle between Remaining and Used display")
    struct DisplayMode {

        @Test
        func `Used mode shows inverted percentage`() {
            // Given — 65% remaining
            let quota = UsageQuota(
                percentRemaining: 65,
                quotaType: .session,
                providerId: "claude"
            )

            // Then — remaining shows 65%, used shows 35%
            #expect(quota.displayPercent(mode: .remaining) == 65)
            #expect(quota.displayPercent(mode: .used) == 35)
        }

        @Test
        func `depleted quota shows 100% used`() {
            let quota = UsageQuota(
                percentRemaining: 0,
                quotaType: .session,
                providerId: "claude"
            )

            #expect(quota.displayPercent(mode: .used) == 100)
        }
    }

    // MARK: - #13: Unavailable provider shows error

    @Suite("Scenario: Unavailable provider shows error message")
    struct ProviderErrors {
        private struct TestClock: Clock {
            func sleep(for duration: TimeInterval) async throws {}
        }

        @Test
        func `unavailable provider has no snapshot after refresh`() async {
            // Given — CLI not found
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(false)

            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot == nil)
        }

        @Test
        func `session expired error is stored on provider`() async {
            // Given — API returns 401
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willThrow(ProbeError.sessionExpired())

            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — error stored, user sees "Session expired..."
            #expect(claude.snapshot == nil)
            #expect(claude.lastError != nil)
            #expect(claude.lastError?.localizedDescription.contains("Session expired") == true)
        }
    }

    // MARK: - #14: Over-quota negative percentages

    @Suite("Scenario: Over-quota displays negative percentages")
    struct OverQuota {

        @Test
        func `negative percentage is depleted status`() {
            let quota = UsageQuota(
                percentRemaining: -98,
                quotaType: .session,
                providerId: "copilot"
            )

            #expect(quota.status == .depleted)
            #expect(quota.percentRemaining == -98)
        }
    }
}
