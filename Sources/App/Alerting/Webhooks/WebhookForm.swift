import SwiftUI
import Domain

/// *Add Webhook* · *Edit #ai-quota*: the URL, a name, the channel, who it is
/// for and what it sends. The URL is never shown again once kept — editing
/// leaves it as it is unless a new one is pasted. `Webhooks` refuses what it
/// won't keep; the form prints the refusal where it belongs.
struct WebhookForm: View {
    /// What the form is for.
    enum Draft: Equatable {
        case adding
        case editing(Webhook)

        var id: String {
            switch self {
            case .adding: "adding"
            case .editing(let webhook): webhook.id
            }
        }
    }

    let draft: Draft
    let providers: [Provider]
    let quotaAlertPercents: [Int]
    let close: () -> Void

    @Environment(Webhooks.self) private var webhooks
    @Environment(\.appTheme) private var theme

    @State private var url = ""
    @State private var name = ""
    @State private var channel = WebhookChannel.slack
    @State private var scope = Webhook.Scope.everyLogin
    @State private var quotaAlerts = true
    @State private var statusAlerts = false
    @State private var recap = false
    @State private var refusal: Webhooks.Refusal?

    init(draft: Draft, providers: [Provider], quotaAlertPercents: [Int], close: @escaping () -> Void) {
        self.draft = draft
        self.providers = providers
        self.quotaAlertPercents = quotaAlertPercents
        self.close = close
        if case .editing(let webhook) = draft {
            _name = State(initialValue: webhook.name)
            _channel = State(initialValue: webhook.channel)
            _scope = State(initialValue: webhook.scope)
            _quotaAlerts = State(initialValue: webhook.sends.quotaAlerts)
            _statusAlerts = State(initialValue: webhook.sends.statusAlerts)
            _recap = State(initialValue: webhook.sends.recap)
        }
    }

    private var editing: Webhook? {
        if case .editing(let webhook) = draft { webhook } else { nil }
    }

    var body: some View {
        SettingsCard {
            HStack {
                Text(editing.map { WebhookWords.editTitle($0.name) } ?? WebhookWords.add)
                    .font(theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                SettingsActionButton(title: WebhookWords.cancel, iconName: "xmark", style: .secondary, action: close)
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 14) {
                field(WebhookWords.urlLabel) {
                    SettingsTextField(placeholder: editing == nil ? WebhookWords.urlPlaceholder : WebhookWords.urlUnchanged,
                                      text: $url)
                        .onChange(of: url) { if case .address = refusal { refusal = nil } }
                    if case .address = refusal, let refusal {
                        refusalText(refusal)
                    }
                    WebhookSecretNote(
                        text: webhooks.urlsAreOutsideKeychain ? WebhookWords.outsideKeychain : WebhookWords.inKeychain,
                        isWarning: webhooks.urlsAreOutsideKeychain
                    )
                }

                field(WebhookWords.nameLabel) {
                    SettingsTextField(placeholder: WebhookWords.namePlaceholder, text: $name)
                }

                field(WebhookWords.channelLabel) {
                    SettingsSegmentedControl(options: WebhookChannel.allCases, label: WebhookWords.channel, selection: $channel)
                }

                field(WebhookWords.scopeLabel) {
                    WebhookScopePicker(scope: $scope, providers: providers)
                }

                field(WebhookWords.sendsLabel) {
                    WebhookCheck(title: WebhookWords.quotaAlerts, hint: WebhookWords.quotaAlertsHint(quotaAlertPercents),
                                 isOn: $quotaAlerts)
                    WebhookCheck(title: WebhookWords.statusAlerts, hint: WebhookWords.statusAlertsHint, isOn: $statusAlerts)
                    WebhookCheck(title: WebhookWords.recap, hint: WebhookWords.recapHint, isOn: $recap)
                    if refusal == .sendsNothing, let refusal {
                        refusalText(refusal)
                    }
                }

                HStack(spacing: 8) {
                    if let editing {
                        SettingsActionButton(title: WebhookWords.remove, iconName: "trash", style: .destructive) {
                            webhooks.remove(editing.id)
                            close()
                        }
                    }
                    Spacer()
                    SettingsActionButton(title: editing == nil ? WebhookWords.add : WebhookWords.save,
                                         iconName: editing == nil ? "plus" : "checkmark", action: save)
                }
            }
        }
    }

    private func save() {
        let sends = Webhook.Sends(quotaAlerts: quotaAlerts, statusAlerts: statusAlerts, recap: recap)
        do {
            if let editing {
                try webhooks.edit(editing.id, url: url.isEmpty ? nil : url, name: name, channel: channel,
                                  scope: scope, sends: sends)
            } else {
                try webhooks.add(url: url, name: name, channel: channel, scope: scope, sends: sends)
            }
            close()
        } catch {
            refusal = error
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsFieldLabel(text: label)
            content()
        }
    }

    private func refusalText(_ refusal: Webhooks.Refusal) -> some View {
        Text(WebhookWords.refusal(refusal))
            .font(theme.font(size: 11, weight: .semibold))
            .foregroundStyle(theme.statusCritical)
    }
}

/// *Every login*, or one provider — a themed field that opens the list.
private struct WebhookScopePicker: View {
    @Binding var scope: Webhook.Scope
    let providers: [Provider]

    @Environment(\.appTheme) private var theme

    private var names: [String: String] {
        Dictionary(providers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        Menu {
            Button(WebhookWords.scope(.everyLogin, names: names)) { scope = .everyLogin }
            Divider()
            ForEach(providers, id: \.id) { provider in
                Button(provider.name) { scope = .provider(provider.id) }
            }
        } label: {
            HStack {
                Text(WebhookWords.scope(scope, names: names))
                    .font(theme.font(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.glassBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// A themed tick box with its words and a hint below them.
private struct WebhookCheck: View {
    let title: String
    let hint: String
    @Binding var isOn: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.glassBackground))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.glassBorder, lineWidth: max(theme.cardBorderWidth, 1)))
                    .overlay {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(theme.textOnAccent)
                        }
                    }
                    .frame(width: 15, height: 15)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(theme.font(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(hint)
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
    }
}
