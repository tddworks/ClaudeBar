import SwiftUI
import Domain
import Infrastructure

/// Sync & Alerts pane: background refresh cadence, the person's quota alerts,
/// and the webhooks they are sent to.
struct SyncAlertsPane: View {
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPane(
            title: "Sync & Alerts",
            subtitle: "Background refresh cadence, the quota alerts you choose, and where else they are sent."
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Background Sync",
                    subtitle: "Keep the menu-bar number fresh in the background. \"Off\" updates only when you open the menu. Never refreshes faster than once a minute."
                ) {
                    Text(settings.refreshInterval.label)
                        .font(theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                }

                SettingsRowDivider()

                VStack(alignment: .leading, spacing: 8) {
                    SettingsFieldLabel(text: "REFRESH INTERVAL")

                    SettingsSegmentedControl(
                        options: RefreshInterval.allCases,
                        label: { $0.label },
                        selection: $settings.refreshInterval
                    )
                }
            }

            QuotaAlertsCard()

            WebhooksCard(providers: monitor.providers.all)
        }
    }
}

/// *Quota alerts*: the person's own percentages, beside the status alerts at
/// 20% and empty (design-concept/quota-alerts).
private struct QuotaAlertsCard: View {
    @Environment(QuotaAlerts.self) private var alerts
    @Environment(\.appTheme) private var theme
    @State private var entry = ""
    @State private var refusal: String?

    var body: some View {
        SettingsCard {
            SettingsRow(
                title: "Quota Alerts",
                subtitle: "Tell me when a login's quota falls below a percentage I pick — once, and again only after it climbs back."
            ) {
                Text("\(alerts.percents.count) / \(QuotaAlerts.most)")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 10) {
                SettingsFieldLabel(text: "ALERT ME BELOW")

                HStack(spacing: 6) {
                    ForEach(alerts.percents, id: \.self) { percent in
                        chip("\(percent)%") { alerts.remove(percent); refusal = nil }
                    }
                    ForEach(QuotaAlerts.alreadyAlerted.sorted(by: >), id: \.self) { percent in
                        chip(percent == 0 ? "Empty · built in" : "\(percent)% · built in", remove: nil)
                    }
                }

                HStack(spacing: 8) {
                    SettingsTextField(placeholder: "35", text: $entry)
                        .frame(width: 72)
                        .onSubmit(add)
                    SettingsActionButton(title: "Add", iconName: "plus", style: .secondary, action: add)
                        .disabled(alerts.percents.count >= QuotaAlerts.most)
                }

                Text(refusal ?? "ClaudeBar already alerts at 20% and when a quota is empty.")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(refusal == nil ? theme.textTertiary : theme.statusWarning)
            }
        }
    }

    private func add() {
        do {
            try alerts.add(entry)
            entry = ""
            refusal = nil
        } catch {
            refusal = error.errorDescription
        }
    }

    private func chip(_ title: String, remove: (() -> Void)?) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(theme.font(size: 12, weight: .semibold))
                .foregroundStyle(remove == nil ? theme.textTertiary : theme.textPrimary)
            if let remove {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Remove \(title)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(remove == nil ? Color.clear : theme.glassBackground))
        .overlay(Capsule().stroke(theme.glassBorder, style: StrokeStyle(lineWidth: theme.cardBorderWidth, dash: remove == nil ? [3] : [])))
    }
}
