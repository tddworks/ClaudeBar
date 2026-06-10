import SwiftUI
import Domain
import Infrastructure

/// Mistral provider configuration card for SettingsView.
struct MistralConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var mistralConfigExpanded: Bool = false
    @State private var mistralProbeMode: MistralProbeMode = .localLogs

    var body: some View {
        DisclosureGroup(isExpanded: $mistralConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            mistralConfigForm
        } label: {
            mistralConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mistralConfigExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            mistralProbeMode = settings.mistral.mistralProbeMode()
        }
    }

    private var mistralConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accentPrimary.opacity(0.2), theme.accentSecondary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Mistral Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Data fetching method")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var mistralConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROBE MODE")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $mistralProbeMode) {
                    ForEach(MistralProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mistralProbeMode) { _, newValue in
                    settings.mistral.setMistralProbeMode(newValue)
                    Task {
                        await monitor.refresh(providerId: "mistral")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(mistralProbeMode == .localLogs ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Logs Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(mistralProbeMode == .localLogs ? theme.textPrimary : theme.textSecondary)

                        Text("Shows token-based cost (in $) from ~/.vibe/logs/session/.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundStyle(mistralProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Code API Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(mistralProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                        Text("Shows monthly usage % via chat.mistral.ai Code API. Set MISTRAL_CHAT_COOKIE env var.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
    }
}
