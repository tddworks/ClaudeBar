import Foundation
import Testing
@testable import Domain
@testable import Infrastructure

/// Vercel's key moves into the vault for the default login only — from the
/// Keychain item the old card used, or from UserDefaults before that.
@Suite
struct VercelCredentialMigrationTests {
    private func stores() -> (UserDefaults, UserDefaultsCredentialRepository, () -> Void) {
        let name = "VercelMigration.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        let secure = UserDefaults(suiteName: name + ".secure")!
        return (defaults, UserDefaultsCredentialRepository(defaults: secure), {
            defaults.removePersistentDomain(forName: name)
            secure.removePersistentDomain(forName: name + ".secure")
        })
    }

    @Test
    func `the old Keychain item moves to the default login and an added login never inherits it`() {
        let (defaults, credentials, cleanUp) = stores()
        defer { cleanUp() }
        credentials.save("old-secure", forKey: CredentialKey.vercelApiKey)
        let vault = ProviderVault(credentials: credentials, legacyStore: defaults)

        #expect(vault.secret("apiKey", provider: "vercel-gateway.work") == nil)
        #expect(vault.secret("apiKey", provider: "vercel-gateway") == "old-secure")
        #expect(credentials.get(forKey: "provider.vercel-gateway.apiKey") == "old-secure")
        #expect(credentials.get(forKey: CredentialKey.vercelApiKey) == nil)
        #expect(vault.delete("apiKey", provider: "vercel-gateway"))
        #expect(vault.secret("apiKey", provider: "vercel-gateway") == nil)
    }

    @Test
    func `a key from before the Keychain moves too`() {
        let (defaults, credentials, cleanUp) = stores()
        defer { cleanUp() }
        defaults.set("older", forKey: "com.claudebar.credentials.vercel-api-key")
        let vault = ProviderVault(credentials: credentials, legacyStore: defaults)

        #expect(vault.secret("apiKey", provider: "vercel-gateway") == "older")
        #expect(defaults.object(forKey: "com.claudebar.credentials.vercel-api-key") == nil)
    }
}
