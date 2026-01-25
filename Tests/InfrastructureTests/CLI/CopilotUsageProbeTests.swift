import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("CopilotUsageProbe Tests")
struct CopilotUsageProbeTests {

    // MARK: - Test Helpers

    private func makeSettingsRepository(
        username: String = "",
        hasToken: Bool = false,
        copilotAuthEnvVar: String = "",
        monthlyLimit: Int? = nil,
        manualOverrideEnabled: Bool = false,
        manualUsageValue: Double? = nil,
        manualUsageIsPercent: Bool = false,
        apiReturnedEmpty: Bool = false,
        lastUsagePeriodMonth: Int? = nil,
        lastUsagePeriodYear: Int? = nil
    ) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(true, forProvider: "copilot")
        if !username.isEmpty {
            repo.saveGithubUsername(username)
        }
        if hasToken {
            repo.saveGithubToken("ghp_test_token")
        }
        if !copilotAuthEnvVar.isEmpty {
            repo.setCopilotAuthEnvVar(copilotAuthEnvVar)
        }
        if let monthlyLimit {
            repo.setCopilotMonthlyLimit(monthlyLimit)
        }
        repo.setCopilotManualOverrideEnabled(manualOverrideEnabled)
        if let manualUsageValue {
            repo.setCopilotManualUsageValue(manualUsageValue)
        }
        repo.setCopilotManualUsageIsPercent(manualUsageIsPercent)
        repo.setCopilotApiReturnedEmpty(apiReturnedEmpty)
        if let lastUsagePeriodMonth, let lastUsagePeriodYear {
            repo.setCopilotLastUsagePeriod(month: lastUsagePeriodMonth, year: lastUsagePeriodYear)
        }
        return repo
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when token and username are configured`() async {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let probe = CopilotUsageProbe(settingsRepository: settings)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when token is missing`() async {
        let settings = makeSettingsRepository(username: "testuser", hasToken: false)
        let probe = CopilotUsageProbe(settingsRepository: settings)

        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable returns false when username is missing`() async {
        let settings = makeSettingsRepository(username: "", hasToken: true)
        let probe = CopilotUsageProbe(settingsRepository: settings)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Tests

    @Test
    func `probe throws authenticationRequired when token is missing`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: false)
        let probe = CopilotUsageProbe(settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed when username is missing`() async throws {
        let settings = makeSettingsRepository(username: "", hasToken: true)
        let probe = CopilotUsageProbe(settingsRepository: settings)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe parses valid response correctly`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2025, "month": 12 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "Copilot Premium Request",
              "model": "Claude Sonnet 4",
              "unitType": "requests",
              "pricePerUnit": 0.04,
              "grossQuantity": 10.0,
              "grossAmount": 0.4,
              "discountQuantity": 10.0,
              "discountAmount": 0.4,
              "netQuantity": 0.0,
              "netAmount": 0.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "copilot")
        #expect(snapshot.accountEmail == "testuser")
        #expect(snapshot.quotas.count == 1)

        let quota = snapshot.quotas.first!
        #expect(quota.quotaType == .session)
        #expect(quota.percentRemaining == 80.0)
        #expect(quota.resetText == "10/50 requests")
    }

    @Test
    func `probe calculates percentage correctly with multiple items`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2025, "month": 12 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "Copilot Premium Request",
              "model": "Claude Sonnet 4",
              "grossQuantity": 15.0
            },
            {
              "product": "Copilot",
              "sku": "Copilot Premium Request",
              "model": "GPT-4o",
              "grossQuantity": 10.0
            },
            {
              "product": "Actions",
              "sku": "Actions Linux",
              "grossQuantity": 1000.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 50.0)
        #expect(quota.resetText == "25/50 requests")
    }

    @Test
    func `probe returns 100 percent remaining when no usage`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2025, "month": 12 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 100.0)
        #expect(quota.resetText == "0/50 requests")
    }

    @Test
    func `probe uses custom monthly limit from settings`() async throws {
        // Business account with 300 limit
        let settings = makeSettingsRepository(username: "testuser", hasToken: true, monthlyLimit: 300)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2025, "month": 12 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "Copilot Premium Request",
              "model": "Claude Sonnet 4",
              "grossQuantity": 100.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // 100/300 = 33.33% used, 66.67% remaining
        #expect(quota.percentRemaining.rounded() == 67.0)
        #expect(quota.resetText == "100/300 requests")
    }

    @Test
    func `probe uses default limit when no custom limit set`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2025, "month": 12 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "Copilot Premium Request",
              "model": "Claude Sonnet 4",
              "grossQuantity": 25.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // Should use default 50 (Free/Pro tier premium requests)
        #expect(quota.percentRemaining == 50.0)
        #expect(quota.resetText == "25/50 requests")
    }

    @Test
    func `probe calculates correctly for Pro Plus account limit`() async throws {
        // Pro+ account with 1500 limit
        let settings = makeSettingsRepository(username: "testuser", hasToken: true, monthlyLimit: 1500)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2025, "month": 12 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "sku": "Copilot Premium Request",
              "model": "Claude Sonnet 4",
              "grossQuantity": 750.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // 750/1500 = 50% used, 50% remaining
        #expect(quota.percentRemaining == 50.0)
        #expect(quota.resetText == "750/1500 requests")
    }

    // MARK: - Manual Override Tests

    @Test
    func `probe sets apiReturnedEmpty flag when API returns empty usageItems`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        // Verify apiReturnedEmpty flag was set (but manual override NOT auto-enabled)
        #expect(settings.copilotApiReturnedEmpty() == true)
        #expect(settings.copilotManualOverrideEnabled() == false)
        
        // Should return 100% remaining (zero usage)
        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 100.0)
    }

    @Test
    func `probe sets apiReturnedEmpty when API has non-Copilot items only`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Actions",
              "sku": "Actions Linux",
              "grossQuantity": 1000.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        // Verify apiReturnedEmpty flag is set even when API returns non-Copilot items
        #expect(settings.copilotApiReturnedEmpty() == true)
        
        // Should return 100% remaining (zero Copilot usage)
        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 100.0)
        #expect(quota.resetText == "0/50 requests")
    }

    @Test
    func `probe uses manual usage when override is enabled`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            monthlyLimit: 300,
            manualOverrideEnabled: true,
            manualUsageValue: 99,
            manualUsageIsPercent: false
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // Manual usage: 99/300 = 33% used, 67% remaining
        #expect(quota.percentRemaining == 67.0)
        #expect(quota.resetText == "99/300 requests (manual)")
    }

    @Test
    func `probe shows manual indicator in resetText when using manual override`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            manualOverrideEnabled: true,
            manualUsageValue: 50,
            manualUsageIsPercent: false
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "grossQuantity": 10.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // Should use manual value (50) not API value (10)
        #expect(quota.resetText?.contains("(manual)") == true)
        #expect(quota.resetText == "50/50 requests (manual)")
    }

    @Test
    func `probe clears apiReturnedEmpty flag when API returns data`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            apiReturnedEmpty: true
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": [
            {
              "product": "Copilot",
              "grossQuantity": 10.0
            }
          ]
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        _ = try await probe.probe()

        // Flag should be cleared when API returns data
        #expect(settings.copilotApiReturnedEmpty() == false)
    }

    @Test
    func `probe throws error when manual override enabled but no value set`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            manualOverrideEnabled: true,
            manualUsageValue: nil  // No value set
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        // Should throw when manual override is on but value is nil
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe handles percentage input correctly`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            monthlyLimit: 300,
            manualOverrideEnabled: true,
            manualUsageValue: 198,  // 198% of quota
            manualUsageIsPercent: true
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // 198% used = -98% remaining (594 requests of 300 limit)
        #expect(quota.percentRemaining == -98.0)
        #expect(quota.resetText == "594/300 requests (manual)")
    }

    @Test
    func `probe allows negative percentages for over-quota usage`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            monthlyLimit: 50,
            manualOverrideEnabled: true,
            manualUsageValue: 99,  // 99 requests of 50 limit
            manualUsageIsPercent: false
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        // 99/50 = -98% remaining
        #expect(quota.percentRemaining == -98.0)
        #expect(quota.resetText == "99/50 requests (manual)")
    }

    @Test
    func `probe clears manual entry when usage period changes`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            monthlyLimit: 300,
            manualOverrideEnabled: true,
            manualUsageValue: 99,
            manualUsageIsPercent: false,
            lastUsagePeriodMonth: 12,  // December
            lastUsagePeriodYear: 2025
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        // Should throw because period changed (Dec 2025 → Jan 2026) and manual value was cleared
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }

        // Verify manual value was cleared
        #expect(settings.copilotManualUsageValue() == nil)
        // Verify period was updated
        #expect(settings.copilotLastUsagePeriodMonth() == 1)
        #expect(settings.copilotLastUsagePeriodYear() == 2026)
    }

    @Test
    func `probe preserves manual entry when period remains same`() async throws {
        let settings = makeSettingsRepository(
            username: "testuser",
            hasToken: true,
            monthlyLimit: 300,
            manualOverrideEnabled: true,
            manualUsageValue: 99,
            manualUsageIsPercent: false,
            lastUsagePeriodMonth: 1,
            lastUsagePeriodYear: 2026
        )
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "timePeriod": { "year": 2026, "month": 1 },
          "user": "testuser",
          "usageItems": []
        }
        """.data(using: .utf8)!

        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        // Manual value should still be there
        #expect(settings.copilotManualUsageValue() == 99)
        
        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 67.0)  // 99/300 = 33% used, 67% remaining
        #expect(quota.resetText == "99/300 requests (manual)")
    }

    // MARK: - Error Handling Tests

    @Test
    func `probe throws authenticationRequired on 401 response`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on 403 response`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((Data(), response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed on invalid JSON`() async throws {
        let settings = makeSettingsRepository(username: "testuser", hasToken: true)
        let mockNetwork = MockNetworkClient()
        let invalidJSON = "not valid json".data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        given(mockNetwork).request(.any).willReturn((invalidJSON, response))

        let probe = CopilotUsageProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }
}
