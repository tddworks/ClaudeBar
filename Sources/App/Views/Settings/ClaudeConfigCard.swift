import SwiftUI
import Domain
import Infrastructure

/// Claude provider configuration card for SettingsView.
struct ClaudeConfigCard: View {
    @ObservedObject var monitor: QuotaMonitor

    @ObservedObject var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var claudeConfigExpanded: Bool = false
    @State private var claudeBudgetExpanded: Bool = false
    @State private var claudeProbeMode: ClaudeProbeMode = .cli
    @State private var claudeCliFallbackEnabled: Bool = true
    @State private var budgetInput: String = ""

    var body: some View {
        VStack(spacing: 12) {
            configCard
            budgetCard
        }
        .onAppear {
            claudeProbeMode = settings.claude.claudeProbeMode()
            claudeCliFallbackEnabled = settings.claude.claudeCliFallbackEnabled()
            if settings.claudeApiBudget > 0 {
                budgetInput = String(describing: settings.claudeApiBudget)
            }
        }
    }

    // MARK: - Config Card

    private var configCard: some View {
        DisclosureGroup(isExpanded: $claudeConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            configForm
        } label: {
            configHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        claudeConfigExpanded.toggle()
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
    }

    private var configHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Text("Data fetching method")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var configForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROBE MODE")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textSecondary)

                Picker("", selection: $claudeProbeMode) {
                    ForEach(ClaudeProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: claudeProbeMode) { newValue in
                    settings.claude.setClaudeProbeMode(newValue)
                    Task {
                        await monitor.refresh(providerId: "claude")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundColor(claudeProbeMode == .cli ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(claudeProbeMode == .cli ? theme.textPrimary : theme.textSecondary)

                        Text("Runs `claude /usage` command. Works with any auth method.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundColor(claudeProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(claudeProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                        Text("Calls Anthropic API directly. Faster, uses OAuth credentials.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }

            if claudeProbeMode == .api {
                let credentialLoader = ClaudeCredentialLoader()
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
                    Text("Run `claude` in terminal to authenticate, then credentials will be available.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textTertiary)
                }

                Toggle(isOn: $claudeCliFallbackEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI fallback")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundColor(theme.textPrimary)
                        Text("Fall back to `claude /usage` if OAuth API is unavailable.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .onChange(of: claudeCliFallbackEnabled) { newValue in
                    settings.claude.setClaudeCliFallbackEnabled(newValue)
                }
            }
        }
    }

    // MARK: - Budget Card

    private var budgetCard: some View {
        DisclosureGroup(isExpanded: $claudeBudgetExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            budgetForm
                .disabled(!settings.claudeApiBudgetEnabled)
                .opacity(settings.claudeApiBudgetEnabled ? 1 : 0.6)
        } label: {
            budgetHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        claudeBudgetExpanded.toggle()
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
    }

    private var budgetHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude API Budget")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Text("Cost threshold warnings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $settings.claudeApiBudgetEnabled)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    private var budgetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MONTHLY BUDGET (USD)")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textSecondary)

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)

                    TextField("", text: $budgetInput, prompt: Text("10.00").foregroundColor(theme.textTertiary))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                        .onChange(of: budgetInput) { newValue in
                            if let value = Decimal(string: newValue) {
                                settings.claudeApiBudget = value
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Get warnings when approaching your budget threshold.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)

                Text("Only applies to Claude API accounts, not Claude Max.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }
        }
    }
}
