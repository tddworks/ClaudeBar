import SwiftUI
import Domain
import Infrastructure

/// Providers pane: master list of every registered provider with enable
/// toggles; selecting a row drills into that provider's configuration.
struct ProvidersPane: View {
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var selectedProviderId: String?

    var body: some View {
        if let providerId = selectedProviderId,
           let provider = monitor.provider(for: providerId) {
            ProviderDetailView(monitor: monitor, provider: provider) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedProviderId = nil
                }
            }
        } else {
            providerList
        }
    }

    private var providerList: some View {
        SettingsPane(
            title: "Providers",
            subtitle: "Enable the assistants you use. Click a provider to configure it."
        ) {
            VStack(spacing: 8) {
                ForEach(monitor.allProviders, id: \.id) { provider in
                    ProviderListRow(monitor: monitor, provider: provider) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProviderId = provider.id
                        }
                    }
                }
            }
        }
    }
}

// MARK: - List Row

private struct ProviderListRow: View {
    let monitor: QuotaMonitor
    let provider: any AIProvider
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var lowestQuota: UsageQuota? {
        provider.snapshot?.lowestQuota
    }

    private var statusText: String {
        guard provider.isEnabled else { return "Disabled" }
        guard let snapshot = provider.snapshot else { return "No data yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: snapshot.capturedAt, relativeTo: Date())
        return "Updated \(relative)"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ProviderIconView(providerId: provider.id, size: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(statusText)
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                if provider.isEnabled, let quota = lowestQuota {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(Int(quota.percentRemaining))%")
                            .font(.system(size: 12, weight: .bold, design: theme.fontDesign))
                            .foregroundStyle(theme.statusColor(for: quota.status))
                            .monospacedDigit()

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(theme.progressTrack)

                                Capsule()
                                    .fill(theme.statusColor(for: quota.status))
                                    .frame(width: geo.size.width * quota.percentRemaining / 100)
                            }
                        }
                        .frame(width: 80, height: 4)
                    }
                }

                SettingsSwitch(isOn: Binding(
                    get: { provider.isEnabled },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setProviderEnabled(provider.id, enabled: newValue)
                        }
                    }
                ))

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                            .stroke(isHovering ? theme.glassHighlight : theme.glassBorder, lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                            .fill(isHovering ? theme.hoverOverlay : Color.clear)
                    )
            )
            .opacity(provider.isEnabled ? 1 : 0.55)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Detail

/// Per-provider configuration: reuses the existing provider config cards
/// from the popover settings, plus the custom web card URL field.
private struct ProviderDetailView: View {
    let monitor: QuotaMonitor
    let provider: any AIProvider
    let onBack: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                backButton

                HStack(spacing: 14) {
                    ProviderIconView(providerId: provider.id, size: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.name)
                            .font(.system(size: 21, weight: .bold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)

                        Text(provider.isEnabled ? "Enabled" : "Disabled")
                            .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(provider.isEnabled ? theme.statusHealthy : theme.textTertiary)
                    }

                    Spacer()

                    SettingsSwitch(isOn: Binding(
                        get: { provider.isEnabled },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                monitor.setProviderEnabled(provider.id, enabled: newValue)
                            }
                        }
                    ))
                }
                .padding(.bottom, 6)

                if provider.isEnabled {
                    configCard

                    SettingsCard {
                        SettingsFieldLabel(text: "CUSTOM WEB CARD")
                            .padding(.bottom, 8)

                        CustomCardURLField(providerId: provider.id)
                    }
                } else {
                    Text("Enable \(provider.name) to configure it.")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text("All Providers")
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(theme.glassBackground)
                    .overlay(Capsule().stroke(theme.glassBorder, lineWidth: 1))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// The provider-specific config card, when one exists.
    @ViewBuilder
    private var configCard: some View {
        switch provider.id {
        case "claude":
            ClaudeConfigCard(monitor: monitor)
        case "codex":
            CodexConfigCard(monitor: monitor)
        case "kimi":
            KimiConfigCard(monitor: monitor)
        case "minimax":
            MiniMaxConfigCard(monitor: monitor)
        case "deepseek":
            DeepSeekConfigCard(monitor: monitor)
        case "alibaba":
            AlibabaConfigCard(monitor: monitor)
        case "mistral":
            MistralConfigCard(monitor: monitor)
        case "vercel-gateway":
            VercelConfigCard(monitor: monitor)
        case "copilot":
            CopilotConfigCard(monitor: monitor)
        case "zai":
            ZaiConfigCard(monitor: monitor)
        case "bedrock":
            BedrockConfigCard(monitor: monitor)
        default:
            if let extProvider = provider as? ExtensionProvider, extProvider.manifest.hasConfig {
                ExtensionConfigCard(
                    provider: extProvider,
                    configRepository: AppSettings.shared.extensionConfig
                )
            }
        }
    }
}
