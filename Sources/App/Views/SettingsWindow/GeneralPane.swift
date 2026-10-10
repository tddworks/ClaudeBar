import SwiftUI
import Domain
import Infrastructure

/// General pane: startup behavior, popover overview, and burn-rate warnings.
struct GeneralPane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Startup behavior and core app preferences."
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Launch at Login",
                    subtitle: "Start ClaudeBar automatically when you sign in to your Mac."
                ) {
                    SettingsSwitch(isOn: $settings.launchAtLogin)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: "Open On",
                    subtitle: "Where the popover lands each time it opens."
                ) {
                    SettingsSegmentedControl(
                        options: PopoverOpensOn.allCases,
                        label: { $0 == .all ? "All" : "Where I Left It" },
                        selection: $settings.popoverOpensOn
                    )
                }

                SettingsRowDivider()

                SettingsRow(
                    title: "Daily Usage Cards",
                    subtitle: "Show per-day usage summaries in the popover."
                ) {
                    SettingsSwitch(isOn: $settings.showDailyUsageCards)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: "Notch Live Activity",
                    subtitle: "Show session and quota state in the notch. Appears only while there is something to report."
                ) {
                    SettingsSwitch(isOn: $settings.notchEnabled)
                }

                SettingsRowDivider()

                SettingsRow(
                    title: "Touch Bar",
                    subtitle: "Show persistent quota and status on the MacBook Touch Bar."
                ) {
                    SettingsSwitch(isOn: $settings.touchBarEnabled)
                }
            }

            SettingsCard {
                SettingsRow(
                    title: "Burn Rate Warnings",
                    subtitle: "Color by projected usage at reset instead of current usage."
                ) {
                    SettingsSwitch(isOn: $settings.burnRateWarningEnabled)
                }

            }
        }
    }
}
