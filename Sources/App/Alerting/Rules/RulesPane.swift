import SwiftUI
import Domain
import Infrastructure

/// *Rules* pane: your own condition on a quota status and your own action —
/// *when my quota drops below 35%, POST to this URL*
/// ([design](docs/features/alerting/rules/design.md)).
///
/// A destination of its own, beside Sync & Alerts' *Quota alerts* and Notify!:
/// a rule reaches an endpoint the person owns, which neither of those does. It
/// reads the domain directly — the rules from `RuleSet`, *Try it* through the
/// same `RuleEngine` a background crossing goes through — and only renders and
/// tells; it compares nothing and decides nothing.
struct RulesPane: View {
    let monitor: QuotaMonitor

    /// The person's rules, saved. Observable, so the list follows an add, an
    /// edit, a switch or a removal.
    let rules: RuleSet

    /// The one engine: *Try it* sends through the same path a refresh does, so
    /// the button proves what a crossing would actually do.
    let engine: RuleEngine

    @Environment(\.appTheme) private var theme

    /// What is being added. Held here, not in the domain: a rule that is not
    /// added yet is not the person's.
    @State private var draft = RuleDraft()

    /// The refusal to add the draft, if any.
    @State private var refusal: String?

    /// The last *Try it* answer, per rule.
    @State private var outcomes: [String: RuleOutcome] = [:]

    /// The rule whose URL is being typed, and the text — a secret is never
    /// echoed back, so a field only ever holds a URL the person is entering.
    @State private var editingURL: [String: String] = [:]

    var body: some View {
        SettingsPane(
            title: "Rules",
            subtitle: "When a quota crosses a line you pick, POST to a webhook you own — a Slack channel, a script, a service. It runs after every refresh, once per crossing, and only for the logins you watch."
        ) {
            if rules.rules.isEmpty {
                emptyCard
            } else {
                ForEach(rules.rules) { rule in
                    ruleCard(rule)
                }
            }

            addCard
        }
    }

    // MARK: - The empty state

    private var emptyCard: some View {
        SettingsCard {
            Text("No rules yet. Add one below: pick when it should fire, where it should POST, and paste the URL.")
                .font(theme.font(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - One saved rule

    /// One saved rule: its condition and action, its switch, its URL, *Try it* and
    /// *Remove*.
    private func ruleCard(_ rule: Rule) -> some View {
        SettingsCard {
            SettingsRow(
                title: whenLine(rule.condition),
                subtitle: actionLine(rule)
            ) {
                SettingsSwitch(isOn: Binding(
                    get: { rule.isOn },
                    set: { rules.setOn($0, for: rule) }
                ))
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SettingsFieldLabel(text: "WEBHOOK URL")

                    Spacer()

                    if rules.hasWebhookURL(for: rule) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("Configured")
                                .font(theme.font(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(theme.statusHealthy)
                    }
                }

                SecureField("", text: urlBinding(rule), prompt: prompt("https://hooks.slack.com/…"))
                    .textFieldStyle(.plain)
                    .font(theme.font(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                            )
                    )

                Text("Kept in the Keychain, never in the rules file and never in a log.")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SettingsActionButton(
                        title: "Save URL",
                        iconName: "link",
                        style: .secondary
                    ) {
                        saveURL(rule)
                    }
                    .disabled((editingURL[rule.id] ?? "").isEmpty)
                    .opacity((editingURL[rule.id] ?? "").isEmpty ? 0.6 : 1)

                    SettingsActionButton(
                        title: "Try it",
                        iconName: "paperplane.fill",
                        isProminent: false
                    ) {
                        Task { await tryIt(rule) }
                    }
                    .disabled(!rules.hasWebhookURL(for: rule))
                    .opacity(rules.hasWebhookURL(for: rule) ? 1 : 0.6)

                    Spacer()

                    Button {
                        remove(rule)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 9))
                            Text("Remove")
                                .font(theme.font(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(theme.statusCritical)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

                if let outcome = outcomes[rule.id] {
                    Text(outcome.message)
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(tone(of: outcome))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Adding a rule

    private var addCard: some View {
        SettingsCard {
            SettingsFieldLabel(text: "WHEN")

            ScrollView(.horizontal, showsIndicators: false) {
                SettingsSegmentedControl(
                    options: RuleDraft.When.allCases,
                    label: { $0.label },
                    selection: $draft.when
                )
            }
            .padding(.top, 6)

            if draft.when == .below {
                HStack(spacing: 8) {
                    SettingsTextField(placeholder: "35", text: $draft.percent)
                        .frame(width: 72)
                    Text("% left")
                        .font(theme.font(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.top, 8)
            }

            SettingsFieldLabel(text: "THEN")
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                SettingsSegmentedControl(
                    options: WebhookChannel.allCases,
                    label: { $0.displayName },
                    selection: $draft.channel
                )
            }
            .padding(.top, 6)

            SettingsFieldLabel(text: "FOR")
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                SettingsSegmentedControl(
                    options: scopeOptions,
                    label: { scopeLabel($0) },
                    selection: $draft.scopeId
                )
            }
            .padding(.top, 6)

            SettingsFieldLabel(text: "WEBHOOK URL")
                .padding(.top, 14)

            SecureField("", text: $draft.url, prompt: prompt("https://hooks.slack.com/…"))
                .textFieldStyle(.plain)
                .font(theme.font(size: 12, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.glassBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                        )
                )
                .padding(.top, 6)

            HStack(spacing: 8) {
                SettingsActionButton(title: "Add Rule", iconName: "plus") {
                    add()
                }

                Text(refusal ?? "It fires once when a login crosses the line, and again only after it climbs back.")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(refusal == nil ? theme.textTertiary : theme.statusWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - The words

    /// The condition in the person's words.
    private func whenLine(_ condition: Rule.Condition) -> String {
        switch condition {
        case .below(let percent): "Below \(percent)%"
        case .critical: "Critical"
        case .depleted: "Depleted"
        }
    }

    /// The action in the person's words: the channel, the scope and the one
    /// throttle.
    private func actionLine(_ rule: Rule) -> String {
        let channel: String
        switch rule.action {
        case .webhook(let payload): channel = "Webhook · \(payload.displayName)"
        }

        let scope: String
        switch rule.scope {
        case .everyLogin: scope = "every login"
        case .provider(let id): scope = "only \(providerName(id))"
        }

        // The one throttle there is, said in the person's words.
        return "\(channel) · \(scope) · once, until it climbs back"
    }

    /// The scope choice's label: *Every login*, or the product's name.
    private func scopeLabel(_ id: String) -> String {
        id.isEmpty ? "Every login" : providerName(id)
    }

    /// A product's name as the lineup prints it, or its id when it is not there.
    private func providerName(_ id: String) -> String {
        monitor.providers.all.first { $0.id == id }?.name ?? id
    }

    /// The scope choices: every login, then each product by its name.
    private var scopeOptions: [String] {
        [""] + monitor.providers.all.map(\.id)
    }

    /// The colour an outcome is shown in.
    private func tone(of outcome: RuleOutcome) -> Color {
        switch outcome {
        case .sent: theme.statusHealthy
        case .nothingToSend: theme.textSecondary
        case .failed: theme.statusCritical
        }
    }

    /// Placeholder text in the tertiary colour.
    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(theme.textTertiary)
    }

    // MARK: - Actions

    /// The URL field for one rule: a secret is never echoed back, so it starts
    /// empty.
    private func urlBinding(_ rule: Rule) -> Binding<String> {
        Binding(
            get: { editingURL[rule.id] ?? "" },
            set: { editingURL[rule.id] = $0 }
        )
    }

    /// Keeps the typed URL on the rule and clears the field.
    private func saveURL(_ rule: Rule) {
        let url = (editingURL[rule.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        rules.update(rule, webhookURL: url)
        editingURL[rule.id] = ""
        outcomes[rule.id] = nil
    }

    /// Forgets the rule and anything the pane held for it.
    private func remove(_ rule: Rule) {
        rules.remove(rule)
        editingURL[rule.id] = nil
        outcomes[rule.id] = nil
    }

    /// Adds the draft as a rule, or refuses with a sentence when it does not spell
    /// one.
    private func add() {
        guard let rule = draft.rule() else {
            refusal = draft.when == .below
                ? "Pick a whole percent between 1 and 99."
                : "Give the rule a condition."
            return
        }

        let url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        rules.add(rule, webhookURL: url.isEmpty ? nil : url)
        draft = RuleDraft()
        refusal = nil
    }

    /// *Try it*: fires now, whatever the condition says, through the engine — a
    /// login in the rule's scope stands in for the one a refresh would judge.
    private func tryIt(_ rule: Rule) async {
        guard let login = monitor.lineup.first(where: { rule.scope.covers(providerId: $0.providerId) }) else {
            outcomes[rule.id] = .nothingToSend
            return
        }
        outcomes[rule.id] = await engine.tryIt(rule, for: monitor.ruleLogin(login), under: monitor.statusPolicy)
    }
}

/// What is being added, before it is a rule: the pane's own draft, with the
/// person's words for each choice.
private struct RuleDraft {
    enum When: String, CaseIterable, Hashable {
        case below, critical, depleted

        /// The condition as the pane names it.
        var label: String {
            switch self {
            case .below: "Below"
            case .critical: "Critical"
            case .depleted: "Depleted"
            }
        }
    }

    var when: When = .below
    var percent: String = "35"
    var channel: WebhookChannel = .slack
    /// `""` is every login; otherwise a product's id.
    var scopeId: String = ""
    var url: String = ""

    /// The rule this draft spells out, or nil when it does not spell one.
    func rule() -> Rule? {
        let condition: Rule.Condition
        switch when {
        case .below:
            guard let percent = Int(percent.trimmingCharacters(in: .whitespaces)), (1...99).contains(percent) else {
                return nil
            }
            condition = .below(percent: percent)
        case .critical:
            condition = .critical
        case .depleted:
            condition = .depleted
        }

        let scope: Rule.Scope = scopeId.isEmpty ? .everyLogin : .provider(scopeId)

        return Rule(condition: condition, action: .webhook(channel: channel), scope: scope)
    }
}