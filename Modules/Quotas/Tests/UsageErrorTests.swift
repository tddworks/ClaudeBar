import Testing
import Foundation
@testable import Quotas

/// What a provider's card says when there is no usage, and when two failures
/// count as the same problem (so a repeat doesn't alert twice).
@Suite
struct UsageErrorTests {
    @Test(arguments: [
        (UsageError.cliNotFound("claude"), "CLI not found: claude"),
        (.authenticationRequired, "Authentication required. Please log in."),
        (.parseFailed("Could not find session usage"), "Failed to parse output: Could not find session usage"),
        (.timeout, "Request timed out"),
        (.noData, "No usage data available"),
        (.updateRequired, "CLI update required"),
        (.folderTrustRequired, "Please trust this folder in Claude CLI"),
        (.executionFailed("Warp: Something broke"), "Warp: Something broke"),
        (.subscriptionRequired, "Subscription required for usage data"),
    ])
    func `should tell the person why there is no usage`(error: UsageError, message: String) {
        #expect(error.errorDescription == message)
    }

    @Test
    func `should say when ClaudeBar will try again after being rate limited`() {
        let error = UsageError.rateLimited(retryAt: Date().addingTimeInterval(30 * 60))
        #expect(error.errorDescription?.hasPrefix("Rate limited. Retrying ") == true)
        #expect(error.errorDescription?.hasSuffix(".") == true)
    }

    @Test
    func `should say a resting login waits for its quota to refill`() {
        let error = UsageError.resting(until: Date().addingTimeInterval(60 * 60))
        #expect(error.errorDescription?.hasPrefix("Resting. Its quota refills ") == true)
        #expect(error.errorDescription?.hasSuffix(".") == true)
    }

    @Test(arguments: [
        UsageError.cliNotFound("claude"), .authenticationRequired, .parseFailed("x"), .timeout, .noData,
        .updateRequired, .folderTrustRequired, .executionFailed("x"), .subscriptionRequired,
        .rateLimited(retryAt: Date(timeIntervalSince1970: 1_000)),
        .resting(until: Date(timeIntervalSince1970: 1_000)),
    ])
    func `should count the same failure twice as the same problem`(error: UsageError) {
        #expect(error == error)
    }

    @Test
    func `should count different failures, or the same one with different details, as different problems`() {
        #expect(UsageError.noData != .timeout)
        #expect(UsageError.cliNotFound("claude") != .cliNotFound("codex"))
        #expect(UsageError.executionFailed("a") != .executionFailed("b"))
        #expect(UsageError.rateLimited(retryAt: Date(timeIntervalSince1970: 1)) != .rateLimited(retryAt: Date(timeIntervalSince1970: 2)))
        #expect(UsageError.resting(until: Date(timeIntervalSince1970: 1)) != .resting(until: Date(timeIntervalSince1970: 2)))
    }
}
