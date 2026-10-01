import SwiftUI
import Domain
import Infrastructure

/// Select providers once, then configure each provider independently.
struct MenuBarPane: View {
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    private var selectedProviders: [any AIProvider] {
        settings.menuBarProviderIds.compactMap { monitor.provider(for: $0) }
    }

    var body: some View {
        SettingsPane(title: "Menu Bar", subtitle: "Choose what appears in your menu bar.") {
            SettingsCard {
                SettingsFieldLabel(text: "QUOTA DISPLAY")
                    .padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(UsageDisplayMode.allCases, id: \.rawValue) { mode in
                        DisplayModeButton(mode: mode, isSelected: settings.usageDisplayMode == mode) {
                            settings.usageDisplayMode = mode
                        }
                    }
                }
                SettingsRowDivider()
                SettingsRow(title: "Show Percentage in Menu Bar", subtitle: "Live quota usage for each selected provider.") {
                    SettingsSwitch(isOn: $settings.menuBarPercentageEnabled)
                }
                SettingsRowDivider()
                SettingsRow(title: "Show Duration in Menu Bar", subtitle: "Time until each quota window resets.") {
                    SettingsSwitch(isOn: $settings.menuBarDurationEnabled)
                }
            }

            if settings.menuBarPercentageEnabled || settings.menuBarDurationEnabled {
                SettingsCard {
                    HStack {
                        SettingsFieldLabel(text: "PROVIDERS")
                        Spacer()
                        Text("\(settings.menuBarProviderIds.count) / 3 selected")
                            .font(.system(size: 11, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Text("Select up to three, then customize each provider below.")
                        .font(.system(size: 11, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, 5)
                        .padding(.bottom, 12)
                    MenuBarChoices {
                        ForEach(monitor.enabledProviders, id: \.id) { provider in
                            let selected = settings.menuBarProviderIds.contains(provider.id)
                            MenuBarProviderChoiceButton(
                                providerId: provider.id, providerName: provider.name, isSelected: selected
                            ) {
                                var ids = settings.menuBarProviderIds
                                if selected { ids.removeAll { $0 == provider.id } }
                                else { ids.append(provider.id) }
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    settings.setMenuBarProviderIds(ids)
                                }
                            }
                            .disabled(selected ? settings.menuBarProviderIds.count == 1 : settings.menuBarProviderIds.count >= 3)
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                        }
                    }
                }
                ForEach(selectedProviders, id: \.id) { provider in
                    MenuBarProviderCard(provider: provider, settings: settings)
                }
            }
        }
    }
}

private struct MenuBarProviderCard: View {
    let provider: any AIProvider
    @Bindable var settings: AppSettings
    @Environment(\.appTheme) private var theme

    private var config: MenuBarProviderSettings { settings.menuBarConfiguration(for: provider.id) }
    private var quotas: [UsageQuota] { provider.snapshot?.quotas ?? [] }
    private var primaryKey: String {
        config.primaryQuotaKey.isEmpty ? (quotas.first?.quotaType.quotaKey ?? "") : config.primaryQuotaKey
    }
    private var secondaryQuotas: [UsageQuota] { quotas.filter { $0.quotaType.quotaKey != primaryKey } }

    private func binding<Value>(_ keyPath: WritableKeyPath<MenuBarProviderSettings, Value>) -> Binding<Value> {
        Binding(get: { config[keyPath: keyPath] }, set: { value in
            var updated = config
            updated[keyPath: keyPath] = value
            let resolvedPrimary = updated.primaryQuotaKey.isEmpty
                ? (quotas.first?.quotaType.quotaKey ?? "") : updated.primaryQuotaKey
            if !resolvedPrimary.isEmpty && updated.secondaryQuotaKey == resolvedPrimary {
                updated.secondaryQuotaKey = ""
            }
            settings.setMenuBarConfiguration(updated, for: provider.id)
        })
    }

    var body: some View {
        SettingsCard {
            HStack(spacing: 10) {
                ProviderIconView(providerId: provider.id, size: 24, showGlow: false)
                Text(provider.name)
                    .font(.system(size: 15, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if settings.menuBarProviderIds.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            settings.setMenuBarProviderIds(settings.menuBarProviderIds.filter { $0 != provider.id })
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(provider.name) from the menu bar")
                    .accessibilityLabel("Remove \(provider.name)")
                }
            }
            if !provider.isEnabled || quotas.isEmpty {
                Text(provider.isEnabled ? "Waiting for quota data… Your choices are saved." : "Enable this provider in Providers to show its usage.")
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
            }
            if !quotas.isEmpty && !config.primaryQuotaKey.isEmpty && !quotas.contains(where: { $0.quotaType.quotaKey == config.primaryQuotaKey }) {
                Text("The saved quota is unavailable. Choose another quota below.")
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.top, 10)
            }
            SettingsRowDivider()
            VStack(alignment: .leading, spacing: 8) {
                SettingsFieldLabel(text: "QUOTA")
                MenuBarChoices {
                    ForEach(quotas, id: \.quotaType.quotaKey) { quota in
                        MenuBarQuotaChoiceButton(
                            title: quota.menuBarTitle ?? quota.quotaType.displayName,
                            isSelected: primaryKey == quota.quotaType.quotaKey
                        ) {
                            binding(\.primaryQuotaKey).wrappedValue = quota.quotaType.quotaKey
                        }
                    }
                }
            }
            if quotas.count > 1 || !config.secondaryQuotaKey.isEmpty {
                SettingsRowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    SettingsFieldLabel(text: "SECONDARY QUOTA")
                    MenuBarChoices {
                        MenuBarChoiceButton(iconName: "minus.circle", label: "None", isSelected: config.secondaryQuotaKey.isEmpty) {
                            binding(\.secondaryQuotaKey).wrappedValue = ""
                        }
                        ForEach(secondaryQuotas, id: \.quotaType.quotaKey) { quota in
                            MenuBarQuotaChoiceButton(
                                title: quota.menuBarTitle ?? quota.quotaType.displayName,
                                isSelected: config.secondaryQuotaKey == quota.quotaType.quotaKey
                            ) {
                                binding(\.secondaryQuotaKey).wrappedValue = quota.quotaType.quotaKey
                            }
                        }
                    }
                }
            }
            if !config.secondaryQuotaKey.isEmpty {
                SettingsRowDivider()
                SettingsRow(title: "Stack in Menu Bar", subtitle: "Draw the two windows as two smaller lines, halving the width.") {
                    SettingsSwitch(isOn: binding(\.stacked))
                }
                if config.stacked {
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsFieldLabel(text: "STACKED TEXT SIZE")
                        HStack(spacing: 8) {
                            ForEach(MenuBarStackedSize.allCases, id: \.rawValue) { size in
                                MenuBarChoiceButton(iconName: size.choiceIconName, label: size.displayLabel,
                                                    isSelected: config.stackedSize == size.rawValue) {
                                    binding(\.stackedSize).wrappedValue = size.rawValue
                                }
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}

/// Keep the existing compact pill spacing; long provider/quota lists scroll.
private struct MenuBarChoices<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
        }
        .clipped()
    }
}
