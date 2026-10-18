import Foundation
import Testing
@testable import Domain

@Suite("ProviderAccountConfig")
struct ProviderAccountConfigTests {

    @Test
    func `should become an account under its provider with its label, email and organization`() {
        let config = ProviderAccountConfig(
            accountId: "work",
            label: "Work Account",
            email: "dev@acme.com",
            organization: "Acme Corp",
            probeConfig: ["profile": "work"]
        )

        let account = config.toProviderAccount(providerId: "claude")

        #expect(account.accountId == "work")
        #expect(account.providerId == "claude")
        #expect(account.label == "Work Account")
        #expect(account.email == "dev@acme.com")
        #expect(account.organization == "Acme Corp")
        #expect(account.id == "claude.work")
    }

    @Test
    func `should become an account with no email or organization when only a label is saved`() {
        let config = ProviderAccountConfig(
            accountId: "personal",
            label: "Personal"
        )

        let account = config.toProviderAccount(providerId: "codex")

        #expect(account.accountId == "personal")
        #expect(account.providerId == "codex")
        #expect(account.label == "Personal")
        #expect(account.email == nil)
        #expect(account.organization == nil)
        #expect(account.id == "codex.personal")
    }

    @Test
    func `should read back the same saved account after writing it to settings`() throws {
        let original = ProviderAccountConfig(
            accountId: "work",
            label: "Work",
            email: "dev@acme.com",
            probeConfig: ["profile": "work", "envVar": "CLAUDE_WORK_TOKEN"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProviderAccountConfig.self, from: data)

        #expect(decoded == original)
    }

    @Test
    func `should differ from another saved account when only the label differs`() {
        let a = ProviderAccountConfig(accountId: "work", label: "Work", email: "a@b.com")
        let b = ProviderAccountConfig(accountId: "work", label: "Work", email: "a@b.com")
        let c = ProviderAccountConfig(accountId: "work", label: "Different", email: "a@b.com")

        #expect(a == b)
        #expect(a != c)
    }
}
