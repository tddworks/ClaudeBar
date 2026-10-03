import SwiftUI
import Domain
import Infrastructure

/// Claude provider configuration card for SettingsView.
struct ClaudeConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
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
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Data fetching method")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var configForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PROBE MODE")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Picker("", selection: $claudeProbeMode) {
                    ForEach(ClaudeProbeMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: claudeProbeMode) { _, newValue in
                    settings.claude.setClaudeProbeMode(newValue)
                    // In API mode ClaudeBar caches usage data for 15 min to stay
                    // under Anthropic's API rate limits, so a faster background
                    // cadence is wasted (calls just return the cache). Snap an
                    // enabled sub-15-min interval up to 15 min (issue #204); leave
                    // "Off" alone so switching mode never turns on sync the user
                    // disabled.
                    if newValue == .api,
                       let seconds = settings.refreshInterval.seconds,
                       seconds < 900 {
                        settings.refreshInterval = .fifteenMinutes
                    }
                    Task {
                        await monitor.refresh(providerId: "claude")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundStyle(claudeProbeMode == .cli ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(claudeProbeMode == .cli ? theme.textPrimary : theme.textSecondary)

                        Text("Runs `claude /usage` command. Works with any auth method.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 10))
                        .foregroundStyle(claudeProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("API Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(claudeProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                        Text("Calls Anthropic API directly. Faster, uses OAuth credentials.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 10))
                        .foregroundStyle(claudeProbeMode == .localFile ? theme.accentPrimary : theme.textTertiary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local File Mode")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(claudeProbeMode == .localFile ? theme.textPrimary : theme.textSecondary)

                        Text("Best-effort: reads today's token count from Claude Desktop's buddy-tokens.json. Shows daily tokens only, no quota windows.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            if claudeProbeMode == .api {
                let credentialLoader = ClaudeCredentialLoader()
                let hasCredentials = credentialLoader.loadCredentials() != nil

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 16)

                    Text("Usage data is cached for 15 min to stay under Anthropic's API rate limits, so background refresh is capped at 15 min in this mode.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                HStack(spacing: 6) {
                    Image(systemName: hasCredentials ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(hasCredentials ? theme.statusHealthy : theme.statusWarning)

                    Text(hasCredentials ? "OAuth credentials found" : "No OAuth credentials found")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(hasCredentials ? theme.statusHealthy : theme.statusWarning)
                }

                if !hasCredentials {
                    Text("Run `claude` in terminal to authenticate, then credentials will be available.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Toggle(isOn: $claudeCliFallbackEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLI fallback")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                        Text("Fall back to `claude /usage` if OAuth API is unavailable.")
                            .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .onChange(of: claudeCliFallbackEnabled) { _, newValue in
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
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude API Budget")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Cost threshold warnings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
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
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)

                    TextField("", text: $budgetInput, prompt: Text("10.00").foregroundStyle(theme.textTertiary))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
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
                        .onChange(of: budgetInput) { _, newValue in
                            if let value = Decimal(string: newValue) {
                                settings.claudeApiBudget = value
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Get warnings when approaching your budget threshold.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Text("Only applies to Claude API accounts, not Claude Max.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
