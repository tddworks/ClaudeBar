import SwiftUI
import Domain
import Infrastructure

/// Codex provider configuration card for SettingsView.
struct CodexConfigCard: View {
    @ObservedObject var monitor: QuotaMonitor

    @ObservedObject var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var codexConfigExpanded: Bool = false
    @State private var codexProbeMode: CodexProbeMode = .rpc

    var body: some View {
        DisclosureGroup(isExpanded: $codexConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            codexConfigForm
        } label: {
            codexConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        codexConfigExpanded.toggle()
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
            codexProbeMode = settings.codex.codexProbeMode()
        }
    }

    private var codexConfigHeader: some View {
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

                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Text("Data fetching method")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var codexConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROBE MODE")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textSecondary)

                Picker("", selection: $codexProbeMode) {
                    ForEach(CodexProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: codexProbeMode) { newValue in
                    settings.codex.setCodexProbeMode(newValue)
                    Task {
                        await monitor.refresh(providerId: "codex")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundColor(codexProbeMode == .rpc ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RPC Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(codexProbeMode == .rpc ? theme.textPrimary : theme.textSecondary)

                        Text("Uses codex app-server via JSON-RPC. Default, works with any auth.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundColor(codexProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(codexProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                        Text("Calls ChatGPT API directly. Faster, uses OAuth credentials.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }

            if codexProbeMode == .api {
                let credentialLoader = CodexCredentialLoader()
                let hasCredentials = credentialLoader.loadCredentials() != nil

                HStack(spacing: 6) {
                    Image(systemName: hasCredentials ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(hasCredentials ? theme.statusHealthy : theme.statusWarning)

                    Text(hasCredentials ? "OAuth credentials found" : "No OAuth credentials found")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(hasCredentials ? theme.statusHealthy : theme.statusWarning)
                }

                if !hasCredentials {
                    Text("Run `codex` in terminal to authenticate, then credentials will be available.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textTertiary)
                }
            }
        }
    }
}
