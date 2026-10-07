import SwiftUI
import Kit

/// Updates pane: Sparkle auto-update controls. In non-Sparkle builds the
/// pane explains that updates are unavailable.
struct UpdatesPane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif

    private var status: UpdateStatus {
        #if ENABLE_SPARKLE
        UpdateStatus(updater: sparkleUpdater)
        #else
        .installed
        #endif
    }

    var body: some View {

        let _ = KitObservation.track()
        SettingsPane(
            title: "Updates",
            subtitle: status.summary
        ) {
            #if ENABLE_SPARKLE
            if sparkleUpdater?.isAvailable == true {
                sparkleContent
            } else {
                unavailableCard
            }
            #else
            unavailableCard
            #endif
        }
    }

    private var unavailableCard: some View {
        SettingsCard {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 10))
                Text("Updates unavailable in debug builds")
                    .font(theme.font(size: 11, weight: .medium))
            }
            .foregroundStyle(theme.textTertiary)
        }
    }

    #if ENABLE_SPARKLE
    @ViewBuilder
    private var sparkleContent: some View {
        SettingsCard {
            SettingsRow(
                title: "Check Automatically",
                subtitle: "Look for new versions in the background."
            ) {
                SettingsSwitch(isOn: Binding(
                    get: { sparkleUpdater?.automaticallyChecksForUpdates ?? true },
                    set: { sparkleUpdater?.automaticallyChecksForUpdates = $0 }
                ))
            }

            SettingsRowDivider()

            SettingsRow(
                title: "Include Beta Versions",
                subtitle: "Get early access to new features."
            ) {
                SettingsSwitch(isOn: $settings.receiveBetaUpdates)
            }
        }

        SettingsCard {
            SettingsRow(
                title: status.actionTitle,
                subtitle: lastCheckText
            ) {
                Button {
                    sparkleUpdater?.checkForUpdates()
                } label: {
                    HStack(spacing: 6) {
                        if sparkleUpdater?.isCheckingForUpdates == true {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: status.availableVersion == nil ? "arrow.clockwise" : "arrow.down.circle")
                                .font(.system(size: 11, weight: .semibold))
                        }

                        Text(sparkleUpdater?.isCheckingForUpdates == true ? "Checking..." : status.buttonTitle)
                            .font(theme.font(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.accentGradient))
                }
                .buttonStyle(.plain)
                .disabled(sparkleUpdater?.canCheckForUpdates != true || sparkleUpdater?.isCheckingForUpdates == true)
                .opacity(sparkleUpdater?.canCheckForUpdates == true ? 1 : 0.6)
            }
        }
    }

    private var lastCheckText: String {
        if let lastCheck = sparkleUpdater?.lastUpdateCheckDate {
            return "Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))"
        } else {
            return "Not checked yet"
        }
    }
    #endif
}
