import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

/// Covers the "app closed" path (issue #201): no language server process, so the probe
/// falls back to the Keychain OAuth token + Google Cloud Code API.
@Suite
struct AntigravityCloudCodeFallbackTests {

    static let noProcessOutput = "12345 /path/to/some_other_binary --flag value"

    static let agyProcessOutput = """
    4242 /opt/homebrew/bin/agy --standalone --csrf_token agy-token-1 --app_data_dir antigravity
    """

    static func keychainBlob(access: String = "ya29.valid", refresh: String? = "1//refresh", expiry: String = "2030-01-01T00:00:00Z") -> String {
        var token: [String: Any] = ["access_token": access, "expiry": expiry]
        if let refresh { token["refresh_token"] = refresh }
        let json = try! JSONSerialization.data(withJSONObject: ["token": token])
        return "go-keyring-base64:" + json.base64EncodedString()
    }

    static let summaryJSON = """
    {"groups":[{"buckets":[
      {"bucketId":"gemini-5h","remainingFraction":0.9,"resetTime":"2025-01-01T05:00:00Z"},
      {"bucketId":"gemini-weekly","remainingFraction":0.7},
      {"bucketId":"3p-5h","remainingFraction":0.5},
      {"bucketId":"3p-weekly","remainingFraction":0.3}
    ]}]}
    """

    static let modelsJSON = """
    {"models":{
      "gemini-3-pro":{"displayName":"Gemini 3 Pro","quotaInfo":{"remainingFraction":0.65}},
      "claude-sonnet":{"displayName":"Claude Sonnet","quotaInfo":{"remainingFraction":0.25}},
      "internal":{"displayName":"Hidden","isInternal":true,"quotaInfo":{"remainingFraction":1.0}}
    }}
    """

    // MARK: - Helpers

    private func makeExecutor(process: String, keychain: CLIResult) -> MockCLIExecutor {
        let mock = MockCLIExecutor()
        given(mock)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, _, _, _, _, _ in
                if binary.hasSuffix("security") { return keychain }
                return CLIResult(output: process, exitCode: 0)
            }
        return mock
    }

    private func http(_ status: Int, _ body: String, url: URL) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    // MARK: - agy CLI process

    @Test
    func `detects the agy CLI language server process`() {
        #expect(AntigravityUsageProbe.isAntigravityProcess(Self.agyProcessOutput))
    }

    @Test
    func `isAvailable returns true when only the agy process is running`() async {
        let executor = makeExecutor(process: Self.agyProcessOutput, keychain: CLIResult(output: "", exitCode: 44))
        let probe = AntigravityUsageProbe(cliExecutor: executor)

        #expect(await probe.isAvailable() == true)
    }

    // MARK: - Availability

    @Test
    func `isAvailable returns true when no process but keychain credentials exist`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let probe = AntigravityUsageProbe(cliExecutor: executor)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when no process and no keychain credentials`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: "not found", exitCode: 44))
        let probe = AntigravityUsageProbe(cliExecutor: executor)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Cloud Code quota summary

    @Test
    func `probe returns pooled quotas from Cloud Code when app is closed`() async throws {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        var authHeaders: [String] = []
        given(remote).request(.any).willProduce { request in
            authHeaders.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            let url = request.url!
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                return self.http(200, Self.summaryJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)
        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "antigravity")
        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.quotas[0].quotaType == .session)
        #expect(snapshot.quotas[0].percentRemaining == 90.0)
        #expect(snapshot.quotas[3].quotaType == .modelSpecific("Claude Weekly"))
        #expect(snapshot.quotas[3].percentRemaining == 30.0)
        #expect(authHeaders.allSatisfy { $0 == "Bearer ya29.valid" })
    }

    /// `pgrep` matching nothing exits with empty output, which the PTY runner reports as
    /// `RunError.timedOut` (issue #301). That still means "not running", so fall back.
    @Test
    func `probe falls back to Cloud Code when pgrep output is empty`() async throws {
        let executor = MockCLIExecutor()
        given(executor)
            .execute(binary: .any, args: .any, input: .any, timeout: .any, workingDirectory: .any, autoResponses: .any)
            .willProduce { binary, _, _, _, _, _ in
                if binary.hasSuffix("security") { return CLIResult(output: Self.keychainBlob(), exitCode: 0) }
                throw InteractiveRunner.RunError.timedOut
            }
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            let url = request.url!
            if url.path.hasSuffix("retrieveUserQuotaSummary") {
                return self.http(200, Self.summaryJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.count == 4)
        #expect(snapshot.quotas[0].percentRemaining == 90.0)
    }

    @Test
    func `probe falls back to fetchAvailableModels when summary endpoint is missing`() async throws {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            let url = request.url!
            if url.path.hasSuffix("fetchAvailableModels") {
                return self.http(200, Self.modelsJSON, url: url)
            }
            return self.http(404, "", url: url)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.count == 2)
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("Gemini 3 Pro") && $0.percentRemaining == 65.0 })
        #expect(snapshot.quotas.contains { $0.quotaType == .modelSpecific("Claude Sonnet") && $0.percentRemaining == 25.0 })
    }

    // MARK: - Errors

    @Test
    func `probe throws cliNotFound when no process and no credentials`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: "not found", exitCode: 44))
        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: MockNetworkClient())

        await #expect(throws: ProbeError.cliNotFound("Antigravity")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws sessionExpired when stored access token is expired`() async {
        let executor = makeExecutor(
            process: Self.noProcessOutput,
            keychain: CLIResult(output: Self.keychainBlob(access: "ya29.stale", expiry: "2020-01-01T00:00:00Z"), exitCode: 0)
        )
        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: MockNetworkClient())

        await #expect(throws: ProbeError.sessionExpired(hint: "Sign in to Antigravity or run `agy` again.")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws sessionExpired when Cloud Code rejects the stored token`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            self.http(401, "", url: request.url!)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)

        await #expect(throws: ProbeError.sessionExpired(hint: "Sign in to Antigravity or run `agy` again.")) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed when Cloud Code is unreachable`() async {
        let executor = makeExecutor(process: Self.noProcessOutput, keychain: CLIResult(output: Self.keychainBlob(), exitCode: 0))
        let remote = MockNetworkClient()
        given(remote).request(.any).willProduce { request in
            self.http(503, "", url: request.url!)
        }

        let probe = AntigravityUsageProbe(cliExecutor: executor, remoteNetworkClient: remote)

        await #expect(throws: ProbeError.executionFailed("Could not reach the Antigravity quota API")) {
            try await probe.probe()
        }
    }
}
