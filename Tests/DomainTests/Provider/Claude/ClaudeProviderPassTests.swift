import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
@MainActor
struct ClaudeProviderPassTests {

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    /// Creates a usage probe that yields a snapshot on the given account tier.
    private func makeUsageProbe(tier: AccountTier?) -> MockUsageProbe {
        let mock = MockUsageProbe()
        given(mock).probe().willReturn(
            UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date(), accountTier: tier)
        )
        given(mock).isAvailable().willReturn(true)
        return mock
    }

    @Test
    func `supportsGuestPasses returns true for a Max account`() async throws {
        let settings = makeSettingsRepository()
        let mockPassProbe = MockClaudePassProbing()
        let claude = ClaudeProvider(
            probe: makeUsageProbe(tier: .claudeMax),
            passProbe: mockPassProbe,
            settingsRepository: settings
        )

        try await claude.refresh()

        #expect(claude.supportsGuestPasses == true)
    }

    @Test
    func `supportsGuestPasses returns false for a Pro account`() async throws {
        // Issue #243: invitation links are Max-only, so Pro accounts must not
        // see the Share button — clicking it could only ever fail.
        let settings = makeSettingsRepository()
        let mockPassProbe = MockClaudePassProbing()
        let claude = ClaudeProvider(
            probe: makeUsageProbe(tier: .claudePro),
            passProbe: mockPassProbe,
            settingsRepository: settings
        )

        try await claude.refresh()

        #expect(claude.supportsGuestPasses == false)
    }

    @Test
    func `supportsGuestPasses returns false for an API account`() async throws {
        let settings = makeSettingsRepository()
        let mockPassProbe = MockClaudePassProbing()
        let claude = ClaudeProvider(
            probe: makeUsageProbe(tier: .claudeApi),
            passProbe: mockPassProbe,
            settingsRepository: settings
        )

        try await claude.refresh()

        #expect(claude.supportsGuestPasses == false)
    }

    @Test
    func `supportsGuestPasses returns false when the account tier is unknown`() async throws {
        let settings = makeSettingsRepository()
        let mockPassProbe = MockClaudePassProbing()
        let claude = ClaudeProvider(
            probe: makeUsageProbe(tier: nil),
            passProbe: mockPassProbe,
            settingsRepository: settings
        )

        try await claude.refresh()

        #expect(claude.supportsGuestPasses == false)
    }

    @Test
    func `supportsGuestPasses returns false before the first refresh`() {
        let settings = makeSettingsRepository()
        let mockPassProbe = MockClaudePassProbing()
        let claude = ClaudeProvider(
            probe: makeUsageProbe(tier: .claudeMax),
            passProbe: mockPassProbe,
            settingsRepository: settings
        )

        #expect(claude.supportsGuestPasses == false)
    }

    @Test
    func `supportsGuestPasses returns false when passProbe is nil`() async throws {
        let settings = makeSettingsRepository()
        let claude = ClaudeProvider(
            probe: makeUsageProbe(tier: .claudeMax),
            settingsRepository: settings
        )

        try await claude.refresh()

        #expect(claude.supportsGuestPasses == false)
    }

    @Test
    func `fetchPasses throws when passProbe is not configured`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

        await #expect(throws: PassError.self) {
            _ = try await claude.fetchPasses()
        }
    }

    @Test
    func `fetchPasses returns pass data on success`() async throws {
        let settings = makeSettingsRepository()
        let expectedPass = ClaudePass(
            passesRemaining: 3,
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willReturn(expectedPass)
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        let pass = try await claude.fetchPasses()

        #expect(pass.passesRemaining == 3)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/ABC123")
    }

    @Test
    func `fetchPasses returns URL when pass count is unknown`() async throws {
        // Simulates clipboard-only mode where count isn't available
        let settings = makeSettingsRepository()
        let expectedPass = ClaudePass(
            referralURL: URL(string: "https://claude.ai/referral/ABC123")!
        )
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willReturn(expectedPass)
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        let pass = try await claude.fetchPasses()

        #expect(pass.passesRemaining == nil)
        #expect(pass.referralURL.absoluteString == "https://claude.ai/referral/ABC123")
    }

    @Test
    func `fetchPasses stores guestPass on success`() async throws {
        let settings = makeSettingsRepository()
        let expectedPass = ClaudePass(
            passesRemaining: 2,
            referralURL: URL(string: "https://claude.ai/referral/XYZ")!
        )
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willReturn(expectedPass)
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        #expect(claude.guestPass == nil)

        _ = try await claude.fetchPasses()

        #expect(claude.guestPass != nil)
        #expect(claude.guestPass?.passesRemaining == 2)
    }

    @Test
    func `fetchPasses tracks isFetchingPasses state`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willReturn(ClaudePass(
            passesRemaining: 1,
            referralURL: URL(string: "https://claude.ai/referral/TEST")!
        ))
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        #expect(claude.isFetchingPasses == false)

        _ = try await claude.fetchPasses()

        // After fetch completes, isFetchingPasses should be false again
        #expect(claude.isFetchingPasses == false)
    }

    @Test
    func `fetchPasses stores passError on failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willThrow(ProbeError.executionFailed("CLI error"))
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        #expect(claude.passError == nil)

        do {
            _ = try await claude.fetchPasses()
        } catch {
            // Expected to throw
        }

        #expect(claude.passError != nil)
    }

    @Test
    func `fetchPasses failure leaves the usage error untouched`() async {
        // A failed invitation-link fetch says nothing about usage data, so it
        // must not make the provider look unavailable in the popover.
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willThrow(ProbeError.executionFailed("CLI error"))
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        do {
            _ = try await claude.fetchPasses()
        } catch {
            // Expected to throw
        }

        #expect(claude.lastError == nil)
    }

    /// Pass probe that fails once, then succeeds — lets a single provider walk
    /// the error-then-recovery path that a fixed stub can't express.
    private final class FailThenSucceedPassProbe: ClaudePassProbing, @unchecked Sendable {
        private var callCount = 0
        let pass = ClaudePass(
            passesRemaining: 1,
            referralURL: URL(string: "https://claude.ai/referral/TEST")!
        )

        func isAvailable() async -> Bool { true }

        func probe() async throws -> ClaudePass {
            callCount += 1
            if callCount == 1 {
                throw ProbeError.executionFailed("CLI error")
            }
            return pass
        }
    }

    @Test
    func `fetchPasses clears a previous passError on success`() async throws {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(
            probe: mockProbe,
            passProbe: FailThenSucceedPassProbe(),
            settingsRepository: settings
        )

        do {
            _ = try await claude.fetchPasses()
        } catch {
            // Expected to throw
        }
        #expect(claude.passError != nil)

        _ = try await claude.fetchPasses()

        #expect(claude.passError == nil)
    }

    @Test
    func `clearPassError removes the stored pass error`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willThrow(ProbeError.executionFailed("CLI error"))
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        do {
            _ = try await claude.fetchPasses()
        } catch {
            // Expected to throw
        }
        #expect(claude.passError != nil)

        claude.clearPassError()

        #expect(claude.passError == nil)
    }
}
