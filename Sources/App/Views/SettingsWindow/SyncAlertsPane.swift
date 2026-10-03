import SwiftUI
import Domain
import Infrastructure

/// Sync & Alerts pane: background refresh cadence and below-threshold alerts.
struct SyncAlertsPane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPane(
            title: "Sync & Alerts",
            subtitle: "Background refresh cadence and quota alert notifications."
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Background Sync",
                    subtitle: "Keep the menu-bar number fresh in the background. \"Off\" updates only when you open the menu. Never refreshes faster than once a minute."
                ) {
                    Text(settings.refreshInterval.label)
                        .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
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

            QuotaAlertThresholdsCard()
        }
    }
}

/// Editor for the user's below-threshold alert list (issue #68). Each stored
/// percentage fires one notification when the worst quota window of a provider
/// falls below it, and again only after the quota recovers past it.
private struct QuotaAlertThresholdsCard: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared
    @State private var newThreshold = ""

    private func percentLabel(_ value: Double) -> String {
        QuotaAlertThreshold(percent: value).displayLabel
    }

    /// Highest first, so the list reads the way the quota falls.
    private var sortedThresholds: [Double] {
        settings.alertThresholds.sorted(by: >)
    }

    var body: some View {
        SettingsCard {
            SettingsRow(
                title: "Below-Threshold Alerts",
                subtitle: "Notify when the lowest quota window of any provider falls below one of these percentages. Each threshold alerts once per crossing, and again only after the quota recovers."
            ) {
                Text("\(settings.alertThresholds.count)/\(AlertThresholdList.maxCount)")
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 10) {
                SettingsFieldLabel(text: "ALERT WHEN REMAINING FALLS BELOW")

                if sortedThresholds.isEmpty {
                    Text("No custom thresholds yet. The built-in status alerts (50%, 20% and 0%) always stay on.")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(sortedThresholds, id: \.self) { threshold in
                            HStack(spacing: 8) {
                                Text("\(percentLabel(threshold))%")
                                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                                    .foregroundStyle(theme.textPrimary)

                                Spacer()

                                Button {
                                    remove(threshold)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove this threshold")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.glassBackground.opacity(0.5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(theme.glassBorder, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("e.g. 35", text: $newThreshold)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                        .onSubmit(add)

                    Button(action: add) {
                        Text("Add")
                            .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.accentPrimary.opacity(0.25))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(theme.accentPrimary.opacity(0.5), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(Double(newThreshold.replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespaces)) == nil)

                    Spacer()
                }

                Text("Fires as a system notification alongside the built-in status alerts.")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func add() {
        guard let updated = AlertThresholdList.adding(newThreshold, to: settings.alertThresholds) else {
            return
        }
        settings.alertThresholds = updated
        newThreshold = ""
    }

    private func remove(_ threshold: Double) {
        settings.alertThresholds.removeAll { $0 == threshold }
    }
}
