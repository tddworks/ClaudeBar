import SwiftUI
import Domain

/// *Webhooks*, under *Quota alerts* in Sync & Alerts (design-concept/webhooks):
/// the person's URLs, each with its channel, scope, switch and last delivery,
/// and the form that adds or edits one. It renders `Webhooks` and tells it;
/// the domain refuses, sends and remembers.
struct WebhooksCard: View {
    /// The providers the scope picker offers, in the pane's order.
    let providers: [Provider]

    @Environment(Webhooks.self) private var webhooks
    @Environment(QuotaAlerts.self) private var quotaAlerts
    @Environment(\.appTheme) private var theme

    /// The form, while the person adds or edits a webhook.
    @State private var form: WebhookForm.Draft?

    private var names: [String: String] {
        Dictionary(providers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(WebhookWords.title)
                        .font(theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(WebhookWords.subtitle)
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if !webhooks.list.isEmpty {
                    SettingsActionButton(title: WebhookWords.add, iconName: "plus") { form = .adding }
                }
            }

            SettingsRowDivider()

            if webhooks.list.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if webhooks.urlsAreOutsideKeychain {
                        WebhookSecretNote(text: WebhookWords.listOutsideKeychain, isWarning: true)
                    }
                    ForEach(webhooks.list) { webhook in
                        WebhookRow(webhook: webhook, scope: WebhookWords.scope(webhook.scope, names: names)) {
                            Task { await webhooks.sendTest(webhook.id) }
                        } edit: {
                            form = .editing(webhook)
                        }
                    }
                }
            }
        }

        if let draft = form {
            WebhookForm(draft: draft, providers: providers, quotaAlertPercents: quotaAlerts.percents) {
                form = nil
            }
            .id(draft.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.dotted")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text(WebhookWords.emptyTitle)
                .font(theme.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(WebhookWords.emptyHint)
                .font(theme.font(size: 11, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            SettingsActionButton(title: WebhookWords.add, iconName: "plus") { form = .adding }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.glassBorder, style: StrokeStyle(lineWidth: max(theme.cardBorderWidth, 1), dash: [5, 4]))
        )
    }
}

/// One webhook: its channel's mark, name and host; *Send a test*, *Edit* and
/// its switch; channel, scope, what it sends and its last delivery.
private struct WebhookRow: View {
    let webhook: Webhook
    let scope: String
    let sendTest: () -> Void
    let edit: () -> Void

    @Environment(Webhooks.self) private var webhooks
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                mark
                VStack(alignment: .leading, spacing: 1) {
                    Text(webhook.name)
                        .font(theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(webhook.host)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SettingsActionButton(title: WebhookWords.sendTest, iconName: "paperplane.fill", style: .secondary,
                                     isBusy: webhook.delivery == .sending, action: sendTest)
                SettingsActionButton(title: WebhookWords.edit, iconName: "pencil", style: .secondary, action: edit)
                SettingsSwitch(isOn: Binding(get: { webhook.isOn }, set: { webhooks.turn(webhook.id, on: $0) }))
            }

            HStack(spacing: 6) {
                WebhookTag(text: WebhookWords.channel(webhook.channel))
                WebhookTag(text: scope)
                Text(WebhookWords.sends(webhook.sends))
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    WebhookDeliveryState(delivery: webhook.delivery, now: context.date)
                }
            }

            if case .failed(let failure, _) = webhook.delivery {
                Text(WebhookWords.failure(failure))
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.statusCritical)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle().fill(theme.statusCritical.opacity(0.6)).frame(height: 1)
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.glassBackground)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
        )
        .opacity(webhook.isOn ? 1 : 0.6)
    }

    /// `#` for Slack, `{}` for JSON.
    private var mark: some View {
        Text(webhook.channel == .slack ? "#" : "{}")
            .font(.system(size: 14, weight: .heavy, design: .monospaced))
            .foregroundStyle(theme.textOnAccent)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(webhook.channel == .slack ? theme.statusWarning : theme.statusHealthy)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
    }
}

/// *Sent 2m ago* · *Failed — 404* · *Nothing sent yet*, with its dot.
private struct WebhookDeliveryState: View {
    let delivery: WebhookDelivery
    let now: Date

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(WebhookWords.delivery(delivery, now: now))
                .font(theme.font(size: 11, weight: .semibold))
                .foregroundStyle(colour)
        }
    }

    private var colour: Color {
        switch delivery {
        case .neverSent: theme.textTertiary
        case .sending: theme.accentPrimary
        case .sent: theme.statusHealthy
        case .failed: theme.statusCritical
        }
    }
}

/// A small inked label: the channel, the scope.
private struct WebhookTag: View {
    let text: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(theme.font(size: 10, weight: .bold))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.accentPrimary.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
    }
}

/// Where the URL is kept: the Keychain, or — on a build it refuses — the app
/// credential store, said plainly.
struct WebhookSecretNote: View {
    let text: String
    let isWarning: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "lock.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(theme.font(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(isWarning ? theme.statusWarning : theme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isWarning ? theme.statusWarning.opacity(0.12) : theme.glassBackground)
        )
    }
}
