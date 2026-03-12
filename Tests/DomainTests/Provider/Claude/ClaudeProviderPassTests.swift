import Testing
import Foundation
import Mockable
@testable import Domain

@Suite
struct ClaudeProviderPassTests {

    /// Creates a mock settings repository that returns true for all providers
    private func makeSettingsRepository() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    func `supportsGuestPasses returns true when passProbe is configured`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        #expect(claude.supportsGuestPasses == true)
    }

    @Test
    func `supportsGuestPasses returns false when passProbe is nil`() {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let claude = ClaudeProvider(probe: mockProbe, settingsRepository: settings)

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
    func `fetchPasses stores error on failure`() async {
        let settings = makeSettingsRepository()
        let mockProbe = MockUsageProbe()
        let mockPassProbe = MockClaudePassProbing()
        given(mockPassProbe).probe().willThrow(ProbeError.executionFailed("CLI error"))
        let claude = ClaudeProvider(probe: mockProbe, passProbe: mockPassProbe, settingsRepository: settings)

        #expect(claude.lastError == nil)

        do {
            _ = try await claude.fetchPasses()
        } catch {
            // Expected to throw
        }

        #expect(claude.lastError != nil)
    }
}
