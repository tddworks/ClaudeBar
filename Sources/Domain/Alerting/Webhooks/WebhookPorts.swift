import Foundation
import Mockable

/// Where the person's webhooks are kept: `alerts.webhooks` in `settings.json`.
/// A destination's own repository, beside `NotifySettingsRepository` — never a
/// provider setting. The URL is never here; host and delivery aren't saved.
@Mockable
public protocol WebhookSettingsRepository: Sendable {
    /// The webhooks as saved, in the order they were added.
    func webhooks() -> [Webhook]
    func setWebhooks(_ webhooks: [Webhook])
}

/// One POST of a body to a webhook's URL. Infrastructure builds the request;
/// nothing that could carry the URL reaches a log. `id` names the webhook in
/// the log instead.
@Mockable
public protocol WebhookSending: Sendable {
    func post(_ body: Data, to address: WebhookAddress, webhook id: String) async -> WebhookPost
}
