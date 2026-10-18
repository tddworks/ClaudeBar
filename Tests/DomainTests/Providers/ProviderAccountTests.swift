import Testing
@testable import Domain

@Suite("ProviderAccount")
struct ProviderAccountTests {

    // MARK: - Identity

    @Test
    func `should be known by the provider's own id when it is the default account`() {
        let account = ProviderAccount(providerId: "claude", label: "Default")

        #expect(account.id == "claude")
        #expect(account.isDefault == true)
    }

    @Test
    func `should be known as provider.account when it is a named account`() {
        let account = ProviderAccount(
            accountId: "personal",
            providerId: "claude",
            label: "Personal"
        )

        #expect(account.id == "claude.personal")
        #expect(account.isDefault == false)
    }

    @Test
    func `should share an id but differ when two accounts of one provider have different labels`() {
        let a = ProviderAccount(accountId: "work", providerId: "claude", label: "Work")
        let b = ProviderAccount(accountId: "work", providerId: "claude", label: "Work Account")

        // Equatable compares all fields, so different labels are not equal
        #expect(a != b)
        // But their IDs match
        #expect(a.id == b.id)
    }

    // MARK: - Display

    @Test
    func `should show the label rather than the email`() {
        let account = ProviderAccount(
            accountId: "work",
            providerId: "claude",
            label: "Work Account",
            email: "work@example.com"
        )

        #expect(account.displayName == "Work Account")
    }

    @Test
    func `should show the email when the account has no label`() {
        let account = ProviderAccount(
            accountId: "work",
            providerId: "claude",
            label: "",
            email: "work@example.com"
        )

        #expect(account.displayName == "work@example.com")
    }

    @Test
    func `should show the account id when the account has neither label nor email`() {
        let account = ProviderAccount(
            accountId: "work",
            providerId: "claude",
            label: ""
        )

        #expect(account.displayName == "work")
    }

    @Test
    func `should show the shown name's first letter uppercased as its initial`() {
        let account = ProviderAccount(
            accountId: "personal",
            providerId: "claude",
            label: "personal account"
        )

        #expect(account.initialLetter == "P")
    }

    // MARK: - Constants

    @Test
    func `should name the default account default`() {
        #expect(ProviderAccount.defaultAccountId == "default")
    }
}
