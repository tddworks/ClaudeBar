import SwiftUI
import Domain
import Infrastructure

/// Appearance pane: theme selection, custom theme import, and status colors.
struct AppearancePane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    var body: some View {
        SettingsPane(
            title: "Appearance",
            subtitle: "Themes apply across the popover, menu bar, and this window."
        ) {
            SettingsCard {
                SettingsFieldLabel(text: "THEME")
                    .padding(.bottom, 10)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(ThemeRegistry.shared.allThemes, id: \.id) { registeredTheme in
                        ThemeOptionButton(
                            themeProvider: registeredTheme,
                            isSelected: settings.themeMode == registeredTheme.id
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                settings.themeMode = registeredTheme.id
                            }
                        }
                    }
                }

                ThemeImportButton()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }

            SettingsCard {
                SettingsFieldLabel(text: "STATUS COLORS")
                    .padding(.bottom, 10)

                SettingsRow(
                    title: "High Contrast",
                    subtitle: "Use a built-in palette that reads clearly on light and dark menu bars."
                ) {
                    SettingsSwitch(isOn: $settings.highContrastEnabled)
                }

                ForEach([QuotaStatus.healthy, .warning, .critical, .depleted], id: \.self) { status in
                    SettingsRowDivider()
                    StatusColorRow(status: status, settings: settings)
                }

                Button("Reset to defaults") {
                    settings.resetStatusColors()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(settings.statusColorOverrides.isEmpty ? theme.textTertiary : theme.accentPrimary)
                .disabled(settings.statusColorOverrides.isEmpty)
                .padding(.top, 14)
            }
        }
    }
}

// MARK: - StatusColorRow

/// One status level: name and threshold, a "Custom" marker with a clear
/// button when the user has picked their own color, and the color well.
private struct StatusColorRow: View {
    let status: QuotaStatus
    let settings: AppSettings

    @Environment(\.appTheme) private var theme

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                if isOverridden {
                    Text("Custom")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.accentPrimary)
                    Button {
                        settings.setStatusColorOverride(nil, for: status)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Use the theme's \(title.lowercased()) color")
                    .accessibilityLabel("Clear custom \(title.lowercased()) color")
                }

                ColorPicker("", selection: pickerBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 32)
                    .accessibilityLabel("\(title) color")
            }
        }
    }

    private var isOverridden: Bool {
        settings.statusColorOverrides[status] != nil
    }

    /// Setting always writes an override; ColorPicker only sets on a real change.
    private var pickerBinding: Binding<Color> {
        Binding(
            get: { settings.statusColorOverrides[status].map { Color($0) } ?? theme.statusColor(for: status) },
            set: { settings.setStatusColorOverride($0.rgbColorValue, for: status) }
        )
    }

    private var title: String {
        switch status {
        case .healthy: "Healthy"
        case .warning: "Warning"
        case .critical: "Critical"
        case .depleted: "Depleted"
        }
    }

    private var subtitle: String {
        switch status {
        case .healthy: "More than 50% remaining"
        case .warning: "20% to 50% remaining"
        case .critical: "Under 20% remaining"
        case .depleted: "Nothing left"
        }
    }
}
