import Foundation
import Domain

/// The person's rules, kept in `~/.claudebar/rules.json`, and each rule's
/// webhook URL, kept in the vault (CANONICAL §5).
///
/// The two halves are deliberately apart. The rules file is plaintext and can be
/// read, copied or attached to a bug report; a webhook URL can carry a token
/// (`hooks.slack.com/services/T…/B…/…`, a signed URL), so it goes to the
/// Keychain-backed store — with the same fallback `NotifySettingsRepository`
/// uses, because a locally built ClaudeBar is ad-hoc signed and its Keychain
/// refuses. It is never written to the rules file.
public final class JSONRuleRepository: RuleRepository, @unchecked Sendable {
    /// Shared instance over the default rules file.
    public static let shared = JSONRuleRepository()

    private let fileURL: URL
    private let secureCredentials: any CredentialRepository
    private let fallbackCredentials: any CredentialRepository
    private let lock = NSLock()

    /// A repository over `fileURL` and the two credential stores: the vault, and
    /// the app store that holds what the Keychain refuses.
    public init(
        fileURL: URL? = nil,
        secureCredentials: any CredentialRepository = KeychainCredentialRepository.shared,
        fallbackCredentials: (any CredentialRepository)? = nil
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.secureCredentials = secureCredentials
        self.fallbackCredentials = fallbackCredentials ?? UserDefaultsCredentialRepository()
    }

    /// `~/.claudebar/rules.json`.
    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar/rules.json")
    }

    // MARK: - RuleRepository

    /// The rules in the file; empty when it is missing or unreadable.
    public func rules() -> [Rule] {
        lock.lock()
        defer { lock.unlock() }
        return readRules()
    }

    /// Writes the rules to the file.
    public func setRules(_ rules: [Rule]) {
        lock.lock()
        defer { lock.unlock() }
        writeRules(rules)
    }

    /// The rule's URL, or nil when it has none. The app store is read first, so a
    /// URL the Keychain refused to update or delete never resurfaces.
    public func webhookURL(forRule ruleId: String) -> String? {
        let key = CredentialKey.ruleWebhookURL(ruleId)
        // The fallback first, not the vault: it holds the newest answer — the
        // URL when the Keychain refused to store it, or an empty tombstone when
        // the Keychain refused to forget it. A Keychain ACL can allow reads
        // while refusing updates and deletes, leaving an older URL readable in
        // the vault; reading the vault first would keep POSTing to an endpoint
        // the person replaced or removed.
        if let fallback = fallbackCredentials.get(forKey: key) {
            return fallback.isEmpty ? nil : fallback
        }
        return secureCredentials.get(forKey: key)
    }

    /// Stores the URL in the vault, falling back to the app store when the Keychain
    /// refuses; an empty or nil URL clears it from both.
    public func setWebhookURL(_ url: String?, forRule ruleId: String) {
        let key = CredentialKey.ruleWebhookURL(ruleId)
        // A pasted URL arrives with stray whitespace; an empty one is the person
        // clearing it, not a request to store a blank secret.
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            // Both stores, unconditionally: leaving a copy in whichever store
            // this build does not read from would resurrect it later. When the
            // Keychain refuses the delete, an empty fallback stands as a
            // tombstone, so the removed URL cannot resurface from the vault.
            let secureDeleted = secureCredentials.delete(forKey: key)
            let fallbackDeleted = fallbackCredentials.delete(forKey: key)
            if !secureDeleted || !fallbackDeleted {
                fallbackCredentials.save("", forKey: key)
            }
            return
        }

        secureCredentials.save(trimmed, forKey: key)

        // Prove it landed, rather than assume: `CredentialRepository.save` cannot
        // report a refusal, and an ad-hoc signed build's Keychain returns
        // errSecAuthFailed (-25293). A release build is unaffected.
        if secureCredentials.get(forKey: key) == trimmed {
            _ = fallbackCredentials.delete(forKey: key)
            return
        }

        AppLog.credentials.warning(
            "A rule's webhook URL could not be stored in the Keychain, keeping it in the app credential store instead"
        )
        fallbackCredentials.save(trimmed, forKey: key)
    }

    // MARK: - File I/O

    /// The file's shape: one object, so a later field has somewhere to go.
    private struct RulesFile: Codable {
        var rules: [Rule]
    }

    /// Decodes the rules file, empty on any failure.
    private func readRules() -> [Rule] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(RulesFile.self, from: data) else {
            return []
        }
        return file.rules
    }

    /// Writes the rules pretty and sorted, creating the folder if needed.
    private func writeRules(_ rules: [Rule]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(RulesFile(rules: rules)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}