import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Copilot Configuration
///
/// Users configure GitHub Copilot with PAT, plan tier, and manual overrides.
///
/// Behaviors covered:
/// - #35: User enters GitHub PAT + username → Copilot quota fetched via API
/// - #36: User sets plan tier → adjusts monthly limit
/// - #37: User enables manual override → enters usage count or percentage
/// - #38: API returns empty → warning banner suggests manual entry
/// - #40: Manual usage auto-clears when billing period changes
@Suite("Feature: Copilot Configuration")
struct CopilotConfigSpec {

    private func makeCopilotSettings(
        enabled: Bool = true,
        monthlyLimit: Int? = nil,
        manualOverride: Bool = false,
        manualUsageValue: Double? = nil,
        manualUsageIsPercent: Bool = false
    ) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(enabled, forProvider: "copilot")
        if let limit = monthlyLimit {
            repo.setCopilotMonthlyLimit(limit)
        }
        repo.setCopilotManualOverrideEnabled(manualOverride)
        if let value = manualUsageValue {
            repo.setCopilotManualUsageValue(value)
        }
        repo.setCopilotManualUsageIsPercent(manualUsageIsPercent)
        return repo
    }

    // MARK: - #35: Authentication and credential management

    @Suite("Scenario: Copilot authentication")
    struct Authentication {

        @Test
        func `saving token and username persists in settings`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "copilot")

            let copilot = CopilotProvider(probe: MockUsageProbe(), settingsRepository: settings)

            // When — user enters credentials
            copilot.saveToken("ghp_test123")
            copilot.username = "testuser"

            // Then
            #expect(copilot.hasToken == true)
            #expect(copilot.username == "testuser")
            #expect(copilot.getToken() == "ghp_test123")
        }

        @Test
        func `deleting credentials clears token and username`() {
            // Given — credentials exist
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setEnabled(true, forProvider: "copilot")

            let copilot = CopilotProvider(probe: MockUsageProbe(), settingsRepository: settings)
            copilot.saveToken("ghp_test123")
            copilot.username = "testuser"

            // When
            copilot.deleteCredentials()

            // Then
            #expect(copilot.hasToken == false)
            #expect(copilot.username == "")
            #expect(copilot.getToken() == nil)
        }
    }

    // MARK: - #36: Plan tier monthly limit

    @Suite("Scenario: Plan tier configuration")
    struct PlanTier {

        @Test
        func `monthly limit is persisted per tier`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Free/Pro default
            #expect(settings.copilotMonthlyLimit() == nil)

            // When — user selects Business tier
            settings.setCopilotMonthlyLimit(300)
            #expect(settings.copilotMonthlyLimit() == 300)

            // When — user selects Enterprise tier
            settings.setCopilotMonthlyLimit(1000)
            #expect(settings.copilotMonthlyLimit() == 1000)

            // When — user selects Pro+
            settings.setCopilotMonthlyLimit(1500)
            #expect(settings.copilotMonthlyLimit() == 1500)
        }
    }

    // MARK: - #37: Manual usage override

    @Suite("Scenario: Manual usage override")
    struct ManualOverride {

        @Test
        func `manual usage value is persisted`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // When — user enters manual usage
            settings.setCopilotManualOverrideEnabled(true)
            settings.setCopilotManualUsageValue(99)
            settings.setCopilotManualUsageIsPercent(false)

            // Then
            #expect(settings.copilotManualOverrideEnabled() == true)
            #expect(settings.copilotManualUsageValue() == 99)
            #expect(settings.copilotManualUsageIsPercent() == false)
        }

        @Test
        func `percentage-based manual usage is supported`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // When — user enters percentage
            settings.setCopilotManualOverrideEnabled(true)
            settings.setCopilotManualUsageValue(198)
            settings.setCopilotManualUsageIsPercent(true)

            // Then
            #expect(settings.copilotManualUsageIsPercent() == true)
            #expect(settings.copilotManualUsageValue() == 198)
        }
    }

    // MARK: - #38: API returns empty

    @Suite("Scenario: API returns empty data")
    struct ApiReturnsEmpty {

        @Test
        func `empty API state is persisted for warning banner`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is false
            #expect(settings.copilotApiReturnedEmpty() == false)

            // When — API returns no data
            settings.setCopilotApiReturnedEmpty(true)

            // Then — persisted for UI to show warning
            #expect(settings.copilotApiReturnedEmpty() == true)
        }
    }

    // MARK: - #40: Manual usage auto-clears on period change

    @Suite("Scenario: Billing period change")
    struct BillingPeriod {

        @Test
        func `usage period is tracked for auto-clear`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // No period set initially
            #expect(settings.copilotLastUsagePeriodMonth() == nil)
            #expect(settings.copilotLastUsagePeriodYear() == nil)

            // When — period is recorded
            settings.setCopilotLastUsagePeriod(month: 1, year: 2026)

            // Then
            #expect(settings.copilotLastUsagePeriodMonth() == 1)
            #expect(settings.copilotLastUsagePeriodYear() == 2026)

            // When — period changes (detected by comparing month/year)
            settings.setCopilotLastUsagePeriod(month: 2, year: 2026)

            // Then — new period, manual usage should be cleared by the probe
            #expect(settings.copilotLastUsagePeriodMonth() == 2)
        }
    }
}
