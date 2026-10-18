import Testing
@testable import Domain

@Suite
struct AccountInfoTests {

    @Test
    func `should name the account by its email`() {
        let info = AccountInfo(email: "user@example.com", organization: "Acme Corp")

        #expect(info.displayName == "user@example.com")
    }

    @Test
    func `should name the account by its organization when it has no email`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(info.displayName == "Acme Corp")
    }

    @Test
    func `should give the account no name when it has neither email nor organization`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.displayName == nil)
    }

    @Test
    func `should count an account with nothing known as empty`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.isEmpty)
    }

    @Test
    func `should not count an account with an email as empty`() {
        let info = AccountInfo(email: "user@example.com", organization: nil)

        #expect(!info.isEmpty)
    }

    @Test
    func `should not count an account with an organization as empty`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(!info.isEmpty)
    }

    @Test
    func `should show the email's first letter, capitalised, as the account's initial`() {
        let info = AccountInfo(email: "user@example.com", organization: nil)

        #expect(info.initialLetter == "U")
    }

    @Test
    func `should show the organization's first letter as the initial when there is no email`() {
        let info = AccountInfo(email: nil, organization: "Acme Corp")

        #expect(info.initialLetter == "A")
    }

    @Test
    func `should show no initial for an account with nothing known`() {
        let info = AccountInfo(email: nil, organization: nil)

        #expect(info.initialLetter == nil)
    }

    @Test
    func `should keep the plan the person signed in with`() {
        let info = AccountInfo(email: "user@example.com", organization: nil, loginMethod: "Claude Max")

        #expect(info.loginMethod == "Claude Max")
    }

    @Test
    func `should treat two accounts with the same email and organization as the same`() {
        let a = AccountInfo(email: "user@example.com", organization: "Org")
        let b = AccountInfo(email: "user@example.com", organization: "Org")

        #expect(a == b)
    }
    // MARK: - Billing Type (#271)

    @Test
    func `should know an Apple-billed account as a subscription (#271)`() {
        let info = AccountInfo(email: "user@example.com", billingType: "apple_subscription")

        #expect(info.isSubscriptionBilled)
    }

    @Test
    func `should know a Stripe-billed account as a subscription (#271)`() {
        let info = AccountInfo(email: "user@example.com", billingType: "stripe_subscription")

        #expect(info.isSubscriptionBilled)
    }

    @Test
    func `should not call a pay-as-you-go account a subscription (#271)`() {
        let info = AccountInfo(email: "user@example.com", billingType: "api")

        #expect(!info.isSubscriptionBilled)
    }

    @Test
    func `should not call an account a subscription when its billing is unknown (#271)`() {
        let info = AccountInfo(email: "user@example.com")

        #expect(!info.isSubscriptionBilled)
    }

    @Test
    func `should still count an account as empty when only its billing is known (#271)`() {
        // `isEmpty` drives the account chip in the UI: a billing type is not a
        // name, so an account that carries nothing else still reads as empty.
        let info = AccountInfo(billingType: "apple_subscription")

        #expect(info.isEmpty)
    }
}
