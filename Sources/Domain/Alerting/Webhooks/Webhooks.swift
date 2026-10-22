import Foundation
import Observation

/// *Webhooks*: the person's list of URLs that hear the alerts ClaudeBar
/// already decides — a Slack channel, a script, a service. A destination like
/// this Mac's notifications: it is told every alert and sends it to each
/// webhook that wants it, once, with no retry. It decides nothing about quota
/// ([design](docs/features/alerting/webhooks/design.md)).
@MainActor
@Observable
public final class Webhooks: AlertDestination {
    /// Why a webhook wasn't added or changed, for the card to word.
    public enum Refusal: Error, Equatable, Sendable {
        case address(WebhookAddress.Refusal)
        /// Neither quota alerts nor status alerts ticked.
        case sendsNothing
    }

    /// The key a webhook's URL is kept under in `DestinationSecrets`.
    nonisolated public static func secretKey(for id: String) -> String { "webhook-url-\(id)" }

    /// The webhooks, in the order they were added.
    public private(set) var list: [Webhook]

    /// Whether a URL is kept in the app credential store because the Keychain
    /// refused it — the card says so.
    public private(set) var urlsAreOutsideKeychain = false

    @ObservationIgnored private let settings: any WebhookSettingsRepository
    @ObservationIgnored private let secrets: any DestinationSecrets
    @ObservationIgnored private let sender: any WebhookSending
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let makeId: () -> String

    public init(
        settings: any WebhookSettingsRepository,
        secrets: any DestinationSecrets,
        sender: any WebhookSending,
        now: @escaping () -> Date = Date.init,
        makeId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.settings = settings
        self.secrets = secrets
        self.sender = sender
        self.now = now
        self.makeId = makeId
        self.list = settings.webhooks().map { saved in
            var webhook = saved
            webhook.host = secrets.get(forKey: Self.secretKey(for: saved.id))
                .flatMap { try? WebhookAddress($0) }?.host ?? ""
            webhook.delivery = .neverSent
            return webhook
        }
        noteWhereURLsAreKept()
    }

    // MARK: - The list

    /// Adds a webhook, switched on. `name` empty means the URL's host.
    @discardableResult
    public func add(url: String, name: String, channel: WebhookChannel, scope: Webhook.Scope,
                    sends: Webhook.Sends) throws(Refusal) -> Webhook {
        let address = try Self.address(url)
        guard !sends.isNothing else { throw .sendsNothing }
        let webhook = Webhook(id: makeId(), name: Self.name(name, or: address), channel: channel, scope: scope,
                              sends: sends, isOn: true, host: address.host)
        secrets.save(address.url.absoluteString, forKey: Self.secretKey(for: webhook.id))
        keep(list + [webhook])
        return webhook
    }

    /// Changes a webhook. `url` nil keeps the URL it has; a new one replaces
    /// it, and the last delivery, which was to the old one, is forgotten.
    public func edit(_ id: String, url: String?, name: String, channel: WebhookChannel, scope: Webhook.Scope,
                     sends: Webhook.Sends) throws(Refusal) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let address = try url.map { text throws(Refusal) in try Self.address(text) }
        guard !sends.isNothing else { throw .sendsNothing }
        var webhook = list[index]
        if let address {
            secrets.save(address.url.absoluteString, forKey: Self.secretKey(for: id))
            webhook.host = address.host
            webhook.delivery = .neverSent
        }
        webhook.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? webhook.host : name
        webhook.channel = channel
        webhook.scope = scope
        webhook.sends = sends
        var list = list
        list[index] = webhook
        keep(list)
    }

    /// Turning off is not removing: it keeps its place, its URL and its last delivery.
    public func turn(_ id: String, on: Bool) {
        update(id) { $0.isOn = on }
        settings.setWebhooks(list)
    }

    /// Removes a webhook and its URL.
    public func remove(_ id: String) {
        secrets.delete(forKey: Self.secretKey(for: id))
        keep(list.filter { $0.id != id })
    }

    // MARK: - Sending

    /// *Send a test*: a body labelled a test, never an alert. It works on a
    /// webhook that is off — it is how the person checks one first.
    public func sendTest(_ id: String) async {
        guard let webhook = list.first(where: { $0.id == id }) else { return }
        await deliver(.test, to: [webhook])
    }

    /// Sends `alert` to every webhook that wants it, all at once.
    public func announce(_ alert: Alert) async {
        await deliver(.alert(alert), to: list.filter { $0.wants(alert) })
    }

    private func deliver(_ message: WebhookBody.Message, to webhooks: [Webhook]) async {
        guard !webhooks.isEmpty else { return }
        let sentAt = now()
        let sends = webhooks.map { webhook in
            (webhook.id,
             WebhookBody(message, channel: webhook.channel, sentAt: sentAt).encoded(),
             secrets.get(forKey: Self.secretKey(for: webhook.id)).flatMap { try? WebhookAddress($0) })
        }
        for webhook in webhooks { update(webhook.id) { $0.delivery = .sending } }
        let sender = sender
        let posts = await withTaskGroup(of: (String, WebhookPost).self) { group in
            for (id, body, address) in sends {
                group.addTask {
                    guard let address else { return (id, .failed(.noURL)) }
                    return (id, await sender.post(body, to: address, webhook: id))
                }
            }
            var posts: [String: WebhookPost] = [:]
            for await (id, post) in group { posts[id] = post }
            return posts
        }
        let at = now()
        for (id, post) in posts {
            update(id) { webhook in
                webhook.delivery = switch post {
                case .sent: .sent(at: at)
                case .failed(let failure): .failed(failure, at: at)
                }
            }
        }
    }

    // MARK: - Keeping

    private func keep(_ webhooks: [Webhook]) {
        list = webhooks
        settings.setWebhooks(webhooks)
        noteWhereURLsAreKept()
    }

    private func update(_ id: String, _ change: (inout Webhook) -> Void) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[index])
    }

    private func noteWhereURLsAreKept() {
        urlsAreOutsideKeychain = list.contains { webhook in
            let key = Self.secretKey(for: webhook.id)
            return secrets.get(forKey: key) != nil && !secrets.isInKeychain(key)
        }
    }

    private static func address(_ text: String) throws(Refusal) -> WebhookAddress {
        do { return try WebhookAddress(text) } catch { throw .address(error) }
    }

    private static func name(_ typed: String, or address: WebhookAddress) -> String {
        let typed = typed.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? address.host : typed
    }
}
