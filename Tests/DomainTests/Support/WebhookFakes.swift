import Foundation
@testable import Domain

/// `alerts.webhooks`, kept in memory.
final class InMemoryWebhookSettings: WebhookSettingsRepository, @unchecked Sendable {
    var saved: [Webhook]
    init(_ saved: [Webhook] = []) { self.saved = saved }
    func webhooks() -> [Webhook] { saved }
    func setWebhooks(_ webhooks: [Webhook]) { saved = webhooks }
}

/// A destination's secrets, kept in memory; `keychainRefuses` stands in for an
/// ad-hoc build, whose secrets land in the fallback.
final class InMemoryDestinationSecrets: DestinationSecrets, @unchecked Sendable {
    var keychain: [String: String] = [:]
    var fallback: [String: String] = [:]
    let keychainRefuses: Bool
    init(keychainRefuses: Bool = false) { self.keychainRefuses = keychainRefuses }

    func save(_ value: String, forKey key: String) {
        if keychainRefuses { fallback[key] = value } else { keychain[key] = value; fallback[key] = nil }
    }
    func get(forKey key: String) -> String? { keychain[key] ?? fallback[key] }
    @discardableResult func delete(forKey key: String) -> Bool { keychain[key] = nil; fallback[key] = nil; return true }
    func isInKeychain(_ key: String) -> Bool { keychain[key] != nil }
}

/// A sender that keeps each POST and answers what the test says, per host.
final class RecordingWebhookSender: WebhookSending, @unchecked Sendable {
    struct Post { let body: Data; let address: WebhookAddress; let webhookId: String }
    private let lock = NSLock()
    private var kept: [Post] = []
    private let answers: [String: WebhookPost]

    init(answers: [String: WebhookPost] = [:]) { self.answers = answers }

    var posts: [Post] { lock.withLock { kept } }

    func post(_ body: Data, to address: WebhookAddress, webhook id: String) async -> WebhookPost {
        lock.withLock { kept.append(Post(body: body, address: address, webhookId: id)) }
        return answers[address.host] ?? .sent
    }
}
