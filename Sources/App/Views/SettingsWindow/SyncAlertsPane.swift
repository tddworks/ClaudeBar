import SwiftUI
import Kit

/// Sync & Alerts pane: background refresh cadence and the person's quota alerts.
struct SyncAlertsPane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    var body: some View {

        let _ = KitObservation.track()
        SettingsPane(
            title: "Sync & Alerts",
            subtitle: "Background refresh cadence, and the quota alerts you choose."
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

        let _ = KitObservation.track()
        SettingsCard {
            SettingsRow(
                title: "Quota Alerts",
                subtitle: "Tell me when a login's quota falls below a percentage I pick — once, and again only after it climbs back."
            ) {
                Text("\(alerts.percentValues.count) / \(QuotaAlerts.most)")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 10) {
                SettingsFieldLabel(text: "ALERT ME BELOW")

                HStack(spacing: 6) {
                    ForEach(alerts.percentValues, id: \.self) { percent in
                        chip("\(percent)%") { alerts.remove(percent: percent); refusal = nil }
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
                        .disabled(alerts.percentValues.count >= QuotaAlerts.most)
                }

                Text(refusal ?? "ClaudeBar already alerts at 20% and when a quota is empty.")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(refusal == nil ? theme.textTertiary : theme.statusWarning)
            }
        }
    }

    private func add() {
        refusal = alerts.add(entry: entry)?.message
        if refusal == nil { entry = "" }
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
