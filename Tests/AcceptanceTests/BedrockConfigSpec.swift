import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Bedrock Configuration
///
/// Users configure AWS profile, regions, and daily budget for
/// Bedrock usage monitoring.
///
/// Behaviors covered:
/// - #43: User sets AWS profile → probe authenticates with that SSO profile
/// - #44: User sets regions → probe queries CloudWatch across those regions
/// - #45: User sets daily budget → shows budget progress bar
@Suite("Feature: Bedrock Configuration")
struct BedrockConfigSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    // MARK: - #43: AWS profile configuration

    @Suite("Scenario: AWS profile configuration")
    struct AWSProfile {

        @Test
        func `profile name is persisted in UserDefaults`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is empty
            #expect(settings.awsProfileName() == "")

            // When — user sets profile
            settings.setAWSProfileName("my-sso-profile")

            // Then
            #expect(settings.awsProfileName() == "my-sso-profile")
        }
    }

    // MARK: - #44: Multi-region configuration

    @Suite("Scenario: Region configuration")
    struct RegionConfig {

        @Test
        func `regions list is persisted`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is empty
            #expect(settings.bedrockRegions().isEmpty)

            // When — user sets regions
            settings.setBedrockRegions(["us-east-1", "us-west-2"])

            // Then
            #expect(settings.bedrockRegions() == ["us-east-1", "us-west-2"])
        }
    }

    // MARK: - #45: Daily budget

    @Suite("Scenario: Daily budget configuration")
    struct DailyBudget {

        @Test
        func `daily budget is persisted`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            // Default is nil
            #expect(settings.bedrockDailyBudget() == nil)

            // When — user sets budget
            settings.setBedrockDailyBudget(50.00)

            // Then
            #expect(settings.bedrockDailyBudget() == 50.00)
        }

        @Test
        func `budget can be cleared`() {
            // Given — budget is set
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
            settings.setBedrockDailyBudget(50.00)
            #expect(settings.bedrockDailyBudget() == 50.00)

            // When — user clears budget
            settings.setBedrockDailyBudget(nil)

            // Then
            #expect(settings.bedrockDailyBudget() == nil)
        }
    }

    // MARK: - Provider defaults to disabled

    @Suite("Scenario: Bedrock provider defaults")
    struct ProviderDefaults {

        @Test
        func `Bedrock defaults to disabled until configured`() {
            // Given
            let suiteName = "com.claudebar.test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let settings = UserDefaultsProviderSettingsRepository(userDefaults: defaults)

            let bedrock = BedrockProvider(probe: MockUsageProbe(), settingsRepository: settings)

            // Then — disabled by default (requires AWS profile setup)
            #expect(bedrock.isEnabled == false)
        }
    }
}
