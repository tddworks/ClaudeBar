import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("CopilotInternalAPIProbe Tests")
struct CopilotInternalAPIProbeTests {

    // MARK: - Test Helpers

    private func makeSettingsRepository(
        hasToken: Bool = false,
        copilotAuthEnvVar: String = ""
    ) -> UserDefaultsProviderSettingsRepository {
        let suiteName = "com.claudebar.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let repo = UserDefaultsProviderSettingsRepository(userDefaults: defaults)
        repo.setEnabled(true, forProvider: "copilot")
        if hasToken {
            repo.saveGithubToken("ghp_test_token")
        }
        if !copilotAuthEnvVar.isEmpty {
            repo.setCopilotAuthEnvVar(copilotAuthEnvVar)
        }
        return repo
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when token is configured`() async {
        let settings = makeSettingsRepository(hasToken: true)
        let probe = CopilotInternalAPIProbe(settingsRepository: settings)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when token is missing`() async {
        let settings = makeSettingsRepository(hasToken: false)
        let probe = CopilotInternalAPIProbe(settingsRepository: settings)

        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `isAvailable does not require username`() async {
        // Unlike Billing API, Internal API doesn't need a username
        let settings = makeSettingsRepository(hasToken: true)
        // No username set
        let probe = CopilotInternalAPIProbe(settingsRepository: settings)

        #expect(await probe.isAvailable() == true)
    }

    // MARK: - Probe Parsing Tests

    @Test
    func `probe parses Business plan response with entitlement 300`() async throws {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "copilot_plan": "business",
          "quota_reset_date": "2026-03-01",
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 300,
              "percent_remaining": 99.3,
              "remaining": 298,
              "unlimited": false,
              "overage_count": 0,
              "overage_permitted": true
            }
          },
          "quota_reset_date_utc": "2026-03-01T00:00:00.000Z"
        }
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willReturn((responseJSON, makeHTTPResponse(statusCode: 200)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "copilot")
        #expect(snapshot.accountEmail == "business")
        #expect(snapshot.quotas.count == 1)

        let quota = snapshot.quotas.first!
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.percentRemaining == 99.3)
        #expect(quota.resetText == "2/300 AI credits")
        #expect(quota.resetsAt != nil)
    }

    @Test
    func `probe parses Pro plan response with entitlement 1500`() async throws {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "copilot_plan": "pro",
          "quota_reset_date": "2026-03-01",
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 1500,
              "percent_remaining": 90.0,
              "remaining": 1350,
              "unlimited": false
            }
          }
        }
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willReturn((responseJSON, makeHTTPResponse(statusCode: 200)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        #expect(snapshot.accountEmail == "pro")
        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 90.0)
        #expect(quota.resetText == "150/1500 AI credits")
        #expect(quota.resetsAt != nil)
    }

    @Test
    func `probe handles unlimited premium interactions`() async throws {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "copilot_plan": "enterprise",
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 0,
              "percent_remaining": 100,
              "remaining": 0,
              "unlimited": true
            }
          }
        }
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willReturn((responseJSON, makeHTTPResponse(statusCode: 200)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 100)
        #expect(quota.resetText == "Unlimited AI credits")
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.resetsAt != nil)
    }

    @Test
    func `probe handles response without premium interactions`() async throws {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()
        // Response with only chat/completions, no premium_interactions
        let responseJSON = """
        {
          "copilot_plan": "free",
          "quota_snapshots": {
            "chat": {
              "entitlement": 50,
              "remaining": 45
            }
          }
        }
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willReturn((responseJSON, makeHTTPResponse(statusCode: 200)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()

        let quota = snapshot.quotas.first!
        #expect(quota.percentRemaining == 100)
        #expect(quota.resetText == "No AI credits quota")
        #expect(quota.quotaType == .timeLimit("Monthly"))
        #expect(quota.resetsAt != nil)
    }

    // MARK: - Error Handling Tests

    @Test
    func `probe throws authenticationRequired when token is missing`() async {
        let settings = makeSettingsRepository(hasToken: false)
        let probe = CopilotInternalAPIProbe(settingsRepository: settings)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired on 401`() async {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()

        given(mockNetwork).request(.any).willReturn((Data(), makeHTTPResponse(statusCode: 401)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on 403`() async {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()

        given(mockNetwork).request(.any).willReturn((Data(), makeHTTPResponse(statusCode: 403)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on 404`() async {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()

        given(mockNetwork).request(.any).willReturn((Data(), makeHTTPResponse(statusCode: 404)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed on invalid JSON`() async {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()
        let invalidJSON = "not valid json".data(using: .utf8)!

        given(mockNetwork).request(.any).willReturn((invalidJSON, makeHTTPResponse(statusCode: 200)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe populates resetsAt with start of next UTC month`() async throws {
        let settings = makeSettingsRepository(hasToken: true)
        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "copilot_plan": "business",
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 300,
              "percent_remaining": 99.3,
              "remaining": 298,
              "unlimited": false
            }
          }
        }
        """.data(using: .utf8)!

        given(mockNetwork).request(.any).willReturn((responseJSON, makeHTTPResponse(statusCode: 200)))

        let probe = CopilotInternalAPIProbe(
            networkClient: mockNetwork,
            settingsRepository: settings
        )

        let snapshot = try await probe.probe()
        let quota = try #require(snapshot.quotas.first)
        let expected = MonthlyResetDate.nextMonthlyResetDate(referenceDate: snapshot.capturedAt)
        #expect(quota.resetsAt == expected)
    }
}
