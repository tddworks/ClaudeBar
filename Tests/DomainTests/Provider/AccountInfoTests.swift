import Testing
@testable import Domain

@Suite
struct AccountInfoTests {

    @Test
    func `displays email as primary display name`() {
        let info = AccountInfo(email: "user@example.com", organization: "Acme Corp")

        #expect(info.displayName == "user@example.com")
    }

    @Test
    func `falls back to organization when email is nil`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(info.displayName == "Acme Corp")
    }

    @Test
    func `displayName is nil when both are nil`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.displayName == nil)
    }

    @Test
    func `isEmpty when no fields are populated`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.isEmpty)
    }

    @Test
    func `is not empty when email is present`() {
        let info = AccountInfo(email: "user@example.com", organization: nil)

        #expect(!info.isEmpty)
    }

    @Test
    func `is not empty when organization is present`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(!info.isEmpty)
    }

    @Test
    func `initial letter from email`() {
        let info = AccountInfo(email: "user@example.com", organization: nil)

        #expect(info.initialLetter == "U")
    }

    @Test
    func `initial letter from organization when no email`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(info.initialLetter == "A")
    }

    @Test
    func `initial letter is nil when empty`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.initialLetter == nil)
    }

    @Test
    func `preserves login method`() {
        let info = AccountInfo(email: "user@example.com", organization: nil, loginMethod: "Claude Max")

        #expect(info.loginMethod == "Claude Max")
    }

    @Test
    func `equatable conformance`() {
        let a = AccountInfo(email: "user@example.com", organization: "Org")
        let b = AccountInfo(email: "user@example.com", organization: "Org")

        #expect(a == b)
    }
    // MARK: - Billing Type (#271)

    @Test
    func `recognizes an Apple-billed subscription`() {
        let info = AccountInfo(email: "user@example.com", billingType: "apple_subscription")

        #expect(info.isSubscriptionBilled)
    }

    @Test
    func `recognizes a Stripe-billed subscription`() {
        let info = AccountInfo(email: "user@example.com", billingType: "stripe_subscription")

        #expect(info.isSubscriptionBilled)
    }

    @Test
    func `does not claim a subscription for a pay-as-you-go account`() {
        let info = AccountInfo(email: "user@example.com", billingType: "api")

        #expect(!info.isSubscriptionBilled)
    }

    @Test
    func `does not claim a subscription when the billing type is unknown`() {
        let info = AccountInfo(email: "user@example.com")

        #expect(!info.isSubscriptionBilled)
    }

    @Test
    func `billing type alone does not make the account displayable`() {
        // `isEmpty` drives the account chip in the UI: a billing type is not a
        // name, so an account that carries nothing else still reads as empty.
        let info = AccountInfo(billingType: "apple_subscription")

        #expect(info.isEmpty)
    }
}
