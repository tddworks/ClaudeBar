import SwiftUI
import Domain
import Infrastructure

/// General pane: startup behavior, popover overview, the usage sections the
/// popover shows, and whether a quota warns when it will run out before it resets.
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
                    title: "All Page Style",
                    subtitle: "How each provider reads on the All page. Rings answer \"which one runs out first\"; bars show every quota, lined up."
                ) {
                    SettingsSegmentedControl(
                        options: AllPageStyle.allCases,
                        label: \.displayLabel,
                        selection: $settings.allPageStyle
                    )
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
                    title: "Usage in the popover",
                    subtitle: "Choose which sections show under the quotas."
                ) {
                    EmptyView()
                }

                ForEach(UsageSection.allCases, id: \.self) { section in
                    SettingsRowDivider()

                    SettingsRow(title: section.title, subtitle: section.subtitle) {
                        SettingsSwitch(isOn: Binding(
                            get: { settings.isShown(section) },
                            set: { settings.setShown(section, $0) }
                        ))
                    }
                }
            }

            SettingsCard {
                SettingsRow(
                    title: "Warn when a quota will run out before it resets",
                    subtitle: "Colours and alerts follow the forecast: a quota turns low when, at its pace, it runs out before it refills."
                ) {
                    SettingsSwitch(isOn: $settings.burnRateWarningEnabled)
                }

            }
        }
    }
}

/// A usage section's name and line in Settings — the App's words, never the
/// section's own.
private extension UsageSection {
    var title: String {
        switch self {
        case .today: "Today"
        case .lastThirtyDays: "Last 30 days"
        case .lastYear: "Last year"
        case .modelMix: "Model mix"
        case .projectMix: "Projects"
        case .weeklyRecap: "Recap"
        }
    }

    var subtitle: String {
        switch self {
        case .today: "Cost, tokens and working time"
        case .lastThirtyDays: "The daily chart"
        case .lastYear: "The year as a heatmap"
        case .modelMix: "Which models you lean on"
        case .projectMix: "Where your usage went, by folder"
        case .weeklyRecap: "The week's and month's story, on the All page"
        }
    }
}
