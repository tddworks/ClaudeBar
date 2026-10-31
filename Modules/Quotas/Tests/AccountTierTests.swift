import Testing
@testable import Quotas

@Suite("AccountTier Tests")
struct AccountTierTests {

    // MARK: - Display Name Tests

    @Test
    func `should name the Claude Max plan Claude Max`() {
        #expect(AccountTier.claudeMax.displayName == "Claude Max")
    }

    @Test
    func `should name the Claude Pro plan Claude Pro`() {
        #expect(AccountTier.claudePro.displayName == "Claude Pro")
    }

    @Test
    func `should name the Claude API plan API Usage`() {
        #expect(AccountTier.claudeApi.displayName == "API Usage")
    }

    @Test
    func `should name another plan by its badge`() {
        #expect(AccountTier.custom("PRO").displayName == "PRO")
    }

    // MARK: - Badge Text Tests

    @Test
    func `should badge the Claude Max plan MAX`() {
        #expect(AccountTier.claudeMax.badgeText == "MAX")
    }

    @Test
    func `should badge the Claude Pro plan PRO`() {
        #expect(AccountTier.claudePro.badgeText == "PRO")
    }

    @Test
    func `should badge the Claude API plan API`() {
        #expect(AccountTier.claudeApi.badgeText == "API")
    }

    @Test
    func `should badge another plan with its own text`() {
        #expect(AccountTier.custom("ULTRA").badgeText == "ULTRA")
    }

    // MARK: - Equality Tests

    @Test
    func `should treat the same plan as the same`() {
        #expect(AccountTier.claudeMax == AccountTier.claudeMax)
        #expect(AccountTier.claudePro == AccountTier.claudePro)
        #expect(AccountTier.claudeApi == AccountTier.claudeApi)
        #expect(AccountTier.custom("PRO") == AccountTier.custom("PRO"))
    }

    @Test
    func `should tell different plans apart`() {
        #expect(AccountTier.claudeMax != AccountTier.claudePro)
        #expect(AccountTier.claudeMax != AccountTier.claudeApi)
        #expect(AccountTier.claudePro != AccountTier.claudeApi)
        #expect(AccountTier.custom("PRO") != AccountTier.custom("ULTRA"))
    }

    @Test
    func `should tell another plan badged PRO apart from Claude Pro`() {
        // .custom("PRO") is NOT the same as .claudePro even though badge text is "PRO"
        #expect(AccountTier.custom("PRO") != AccountTier.claudePro)
    }
}
