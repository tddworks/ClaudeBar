import Testing
@testable import Domain

@Suite("AccountTier Tests")
struct AccountTierTests {

    // MARK: - Display Name Tests

    @Test
    func `claudeMax has correct display name`() {
        #expect(AccountTier.claudeMax.displayName == "Claude Max")
    }

    @Test
    func `claudePro has correct display name`() {
        #expect(AccountTier.claudePro.displayName == "Claude Pro")
    }

    @Test
    func `claudeApi has correct display name`() {
        #expect(AccountTier.claudeApi.displayName == "API Usage")
    }

    @Test
    func `custom tier uses badge as display name`() {
        #expect(AccountTier.custom("PRO").displayName == "PRO")
    }

    // MARK: - Badge Text Tests

    @Test
    func `claudeMax has correct badge text`() {
        #expect(AccountTier.claudeMax.badgeText == "MAX")
    }

    @Test
    func `claudePro has correct badge text`() {
        #expect(AccountTier.claudePro.badgeText == "PRO")
    }

    @Test
    func `claudeApi has correct badge text`() {
        #expect(AccountTier.claudeApi.badgeText == "API")
    }

    @Test
    func `custom tier has correct badge text`() {
        #expect(AccountTier.custom("ULTRA").badgeText == "ULTRA")
    }

    // MARK: - Guest Pass Eligibility Tests

    @Test
    func `claudeMax is eligible for guest passes`() {
        #expect(AccountTier.claudeMax.supportsGuestPasses == true)
    }

    @Test
    func `claudePro is not eligible for guest passes`() {
        // Anthropic only issues Claude Code invitation links to Max subscribers.
        #expect(AccountTier.claudePro.supportsGuestPasses == false)
    }

    @Test
    func `claudeApi is not eligible for guest passes`() {
        #expect(AccountTier.claudeApi.supportsGuestPasses == false)
    }

    @Test
    func `custom tier is not eligible for guest passes`() {
        #expect(AccountTier.custom("MAX").supportsGuestPasses == false)
        #expect(AccountTier.custom("ULTRA").supportsGuestPasses == false)
    }

    // MARK: - Equality Tests

    @Test
    func `account tiers are equal when same`() {
        #expect(AccountTier.claudeMax == AccountTier.claudeMax)
        #expect(AccountTier.claudePro == AccountTier.claudePro)
        #expect(AccountTier.claudeApi == AccountTier.claudeApi)
        #expect(AccountTier.custom("PRO") == AccountTier.custom("PRO"))
    }

    @Test
    func `account tiers are not equal when different`() {
        #expect(AccountTier.claudeMax != AccountTier.claudePro)
        #expect(AccountTier.claudeMax != AccountTier.claudeApi)
        #expect(AccountTier.claudePro != AccountTier.claudeApi)
        #expect(AccountTier.custom("PRO") != AccountTier.custom("ULTRA"))
    }

    @Test
    func `custom tier is not equal to Claude tier with same badge`() {
        // .custom("PRO") is NOT the same as .claudePro even though badge text is "PRO"
        #expect(AccountTier.custom("PRO") != AccountTier.claudePro)
    }
}
