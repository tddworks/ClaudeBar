import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct ClaudeAccountInfoResolverTests {

    @Test
    func `resolves email and displayName from oauthAccount`() {
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "accountUuid": "abc-123",
                "emailAddress": "user@example.com",
                "organizationUuid": "org-456",
                "displayName": "testuser",
                "billingType": "stripe_subscription"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result?.email == "user@example.com")
        #expect(result?.organization == "testuser")
    }

    @Test
    func `resolves email only when displayName is absent`() {
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "emailAddress": "user@example.com"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result?.email == "user@example.com")
        #expect(result?.organization == nil)
    }

    @Test
    func `resolves displayName only when email is absent`() {
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "displayName": "testuser"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result?.email == nil)
        #expect(result?.organization == "testuser")
    }

    @Test
    func `returns nil when config file does not exist`() {
        let bogusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        let resolver = ClaudeAccountInfoResolver(configURL: bogusURL)

        let result = resolver.resolve()

        #expect(result == nil)
    }

    @Test
    func `returns nil when oauthAccount section is missing`() {
        let resolver = makeResolverWithConfig("""
        { "numStartups": 100 }
        """)

        let result = resolver.resolve()

        #expect(result == nil)
    }

    @Test
    func `returns nil when oauthAccount has neither email nor displayName`() {
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "accountUuid": "abc-123",
                "organizationUuid": "org-456"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result == nil)
    }

    @Test
    func `returns nil when config file is invalid JSON`() {
        let resolver = makeResolverWithConfig("not valid json {{{")

        let result = resolver.resolve()

        #expect(result == nil)
    }

    @Test
    func `resolves the account's billing type`() {
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "emailAddress": "user@example.com",
                "billingType": "apple_subscription"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result?.billingType == "apple_subscription")
        #expect(result?.isSubscriptionBilled == true)
    }

    @Test
    func `resolves a billing type even when the account has no name`() {
        // The billing type decides whether a `/usage` cost panel means "this is
        // an API account" or "the CLI could not see the subscription" (#271),
        // so it is worth resolving on its own.
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "accountUuid": "abc-123",
                "billingType": "stripe_subscription"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result?.isSubscriptionBilled == true)
        #expect(result?.isEmpty == true)
    }

    @Test
    func `leaves the billing type nil when the account does not carry one`() {
        let resolver = makeResolverWithConfig("""
        {
            "oauthAccount": {
                "emailAddress": "user@example.com"
            }
        }
        """)

        let result = resolver.resolve()

        #expect(result?.billingType == nil)
        #expect(result?.isSubscriptionBilled == false)
    }

    // MARK: - Helpers

    private func makeResolverWithConfig(_ json: String) -> ClaudeAccountInfoResolver {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let configFile = tempDir.appendingPathComponent(".claude.json")
        try! json.data(using: .utf8)!.write(to: configFile)
        return ClaudeAccountInfoResolver(configURL: configFile)
    }
}
