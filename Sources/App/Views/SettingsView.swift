import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Inline settings content view that fits within the menu bar popup.
struct SettingsContentView: View {
    @Binding var showSettings: Bool
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif

    // Token input state
    @State private var copilotTokenInput: String = ""
    @State private var showToken: Bool = false
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false
    @State private var copilotIsExpanded: Bool = false
    @State private var claudeBudgetExpanded: Bool = false
    @State private var providersExpanded: Bool = false
    @State private var zaiConfigExpanded: Bool = false
    @State private var updatesExpanded: Bool = false
    @State private var backgroundSyncExpanded: Bool = false

    // Budget input state
    @State private var budgetInput: String = ""

    @State private var zaiConfigPathInput: String = ""
    @State private var glmAuthEnvVarInput: String = ""
    @State private var copilotAuthEnvVarInput: String = ""
    @State private var isTestingCopilot = false
    @State private var copilotTestResult: String?

    // Bedrock settings state
    @State private var bedrockConfigExpanded: Bool = false
    @State private var awsProfileNameInput: String = ""
    @State private var bedrockRegionsInput: String = ""
    @State private var bedrockDailyBudgetInput: String = ""

    private enum ProviderID {
        static let claude = "claude"
        static let copilot = "copilot"
        static let zai = "zai"
        static let bedrock = "bedrock"
    }

    /// The Copilot provider from the monitor (cast to CopilotProvider for credential access)
    private var copilotProvider: CopilotProvider? {
        monitor.provider(for: ProviderID.copilot) as? CopilotProvider
    }

    /// Binding to the Copilot provider's username
    private var copilotUsernameBinding: Binding<String> {
        Binding(
            get: { copilotProvider?.username ?? "" },
            set: { newValue in copilotProvider?.username = newValue }
        )
    }

    private var isCopilotEnabled: Bool {
        monitor.provider(for: ProviderID.copilot)?.isEnabled ?? false
    }

    private var isZaiEnabled: Bool {
        monitor.provider(for: ProviderID.zai)?.isEnabled ?? false
    }

    private var isClaudeEnabled: Bool {
        monitor.provider(for: ProviderID.claude)?.isEnabled ?? false
    }

    private var isBedrockEnabled: Bool {
        monitor.provider(for: ProviderID.bedrock)?.isEnabled ?? false
    }

    /// Maximum height for the settings view to ensure it fits on small screens
    private var maxSettingsHeight: CGFloat {
        // Use 80% of screen height or 550pt, whichever is smaller
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return min(screenHeight * 0.8, 550)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    themeCard
                    providersCard
                    if isClaudeEnabled {
                        claudeBudgetCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isCopilotEnabled {
                        copilotCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isZaiEnabled {
                        zaiConfigCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isBedrockEnabled {
                        bedrockConfigCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    backgroundSyncCard
                    #if ENABLE_SPARKLE
                    updatesCard
                    #endif
                    logsCard
                    aboutCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxHeight: maxSettingsHeight)
        .onAppear {
            // Initialize budget input with current value
            if settings.claudeApiBudget > 0 {
                budgetInput = String(describing: settings.claudeApiBudget)
            }
            zaiConfigPathInput = UserDefaultsProviderSettingsRepository.shared.zaiConfigPath()
            glmAuthEnvVarInput = UserDefaultsProviderSettingsRepository.shared.glmAuthEnvVar()
            copilotAuthEnvVarInput = UserDefaultsProviderSettingsRepository.shared.copilotAuthEnvVar()

            // Initialize Bedrock settings
            awsProfileNameInput = UserDefaultsProviderSettingsRepository.shared.awsProfileName()
            bedrockRegionsInput = UserDefaultsProviderSettingsRepository.shared.bedrockRegions().joined(separator: ", ")
            if let budget = UserDefaultsProviderSettingsRepository.shared.bedrockDailyBudget() {
                bedrockDailyBudgetInput = String(describing: budget)
            }
        }
    }

    // MARK: - Theme Card

    /// Convert ThemeMode to string for settings storage
    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: currentThemeMode.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("Choose your theme")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            // Theme options grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                    ThemeOptionButton(
                        mode: mode,
                        isSelected: currentThemeMode == mode
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            settings.themeMode = mode.rawValue
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Providers Card

    private var providersCard: some View {
        DisclosureGroup(isExpanded: $providersExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            // Provider toggles
            VStack(spacing: 8) {
                ForEach(monitor.allProviders, id: \.id) { provider in
                    providerToggleRow(provider: provider)
                }
            }
        } label: {
            providersHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        providersExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    private var providersHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Providers")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Enable or disable AI providers")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private func providerToggleRow(provider: any AIProvider) -> some View {
        HStack(spacing: 10) {
            // Provider icon
            ProviderIconView(providerId: provider.id, size: 20)

            Text(provider.name)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { provider.isEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        monitor.setProviderEnabled(provider.id, enabled: newValue)
                        if !newValue {
                            switch provider.id {
                            case ProviderID.copilot:
                                copilotIsExpanded = false
                            case ProviderID.zai:
                                zaiConfigExpanded = false
                            case ProviderID.claude:
                                claudeBudgetExpanded = false
                            case ProviderID.bedrock:
                                bedrockConfigExpanded = false
                            default:
                                break
                            }
                        }
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            .scaleEffect(0.8)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Back button
            Button {
                // Avoid window resize animation glitches in MenuBarExtra.
                showSettings = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Back")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(theme.glassBackground)
                        .overlay(
                            Capsule()
                                .stroke(theme.glassBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Settings")
                .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            // Invisible placeholder to balance the header
            Color.clear
                .frame(width: 60, height: 1)
        }
    }

    // MARK: - Claude Budget Card

    private var claudeBudgetCard: some View {
        DisclosureGroup(isExpanded: $claudeBudgetExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            claudeBudgetForm
                .disabled(!settings.claudeApiBudgetEnabled)
                .opacity(settings.claudeApiBudgetEnabled ? 1 : 0.6)
        } label: {
            // Header row with icon, title, toggle
            claudeBudgetHeader
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

    private var claudeBudgetHeader: some View {
        HStack(spacing: 10) {
            // Provider icon
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

    private var claudeBudgetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Budget Amount
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

            // Help text
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

    // MARK: - Copilot Card

    private var copilotCard: some View {
        DisclosureGroup(isExpanded: $copilotIsExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            copilotForm
        } label: {
            copilotHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        copilotIsExpanded.toggle()
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

    private var copilotHeader: some View {
        HStack(spacing: 10) {
            // Provider icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.38, green: 0.55, blue: 0.93),
                                Color(red: 0.55, green: 0.40, blue: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub Copilot Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Premium usage tracking")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var copilotForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // GitHub Username
            VStack(alignment: .leading, spacing: 6) {
                Text("GITHUB USERNAME")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                TextField("", text: copilotUsernameBinding, prompt: Text("username").foregroundStyle(theme.textTertiary))
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
            }

            // Personal Access Token
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PERSONAL ACCESS TOKEN")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer()

                    if copilotProvider?.hasToken == true {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("Configured")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(theme.statusHealthy)
                    }
                }

                HStack(spacing: 6) {
                    // Token input field
                    Group {
                        if showToken {
                            TextField("", text: $copilotTokenInput, prompt: Text("ghp_xxxx...").foregroundStyle(theme.textTertiary))
                        } else {
                            SecureField("", text: $copilotTokenInput, prompt: Text("ghp_xxxx...").foregroundStyle(theme.textTertiary))
                        }
                    }
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

                    // Eye button
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(theme.glassBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Status messages
                if let error = saveError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(error)
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.statusCritical)
                } else if saveSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("Token saved!")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.statusHealthy)
                }
            }

            // Environment Variable (Alternative)
            VStack(alignment: .leading, spacing: 6) {
                Text("AUTH TOKEN ENV VAR (ALTERNATIVE)")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                TextField("", text: $copilotAuthEnvVarInput, prompt: Text("GITHUB_TOKEN").foregroundStyle(theme.textTertiary))
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
                    .onChange(of: copilotAuthEnvVarInput) { _, newValue in
                        UserDefaultsProviderSettingsRepository.shared.setCopilotAuthEnvVar(newValue)
                    }
            }

            // Explanatory text
            VStack(alignment: .leading, spacing: 4) {
                Text("TOKEN LOOKUP ORDER")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Text("1. First checks environment variable if specified")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                Text("2. Falls back to direct token entry above")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            // Save & Test button
            if isTestingCopilot {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Testing connection...")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Button {
                    Task {
                        await testCopilotConnection()
                    }
                } label: {
                    Text("Save & Test Connection")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
            }

            if let result = copilotTestResult {
                Text(result)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(result.contains("Success") ? theme.statusHealthy : theme.statusCritical)
            }

            // Help text and link
            VStack(alignment: .leading, spacing: 4) {
                Text("Create a fine-grained PAT with 'Plan: read' permission")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Link(destination: URL(string: "https://github.com/settings/tokens?type=beta")!) {
                    HStack(spacing: 3) {
                        Text("Create token on GitHub")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }

            // Delete token
            if copilotProvider?.hasToken == true {
                Button {
                    deleteToken()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9))
                        Text("Remove Token")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.statusCritical)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Z.ai Config Card

    private var zaiConfigCard: some View {
        DisclosureGroup(isExpanded: $zaiConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                // Explanation text
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOKEN LOOKUP ORDER")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Text("1. First looks for token in the settings.json file")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                    Text("2. Falls back to environment variable if not found in file")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTINGS.JSON PATH")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $zaiConfigPathInput, prompt: Text("~/.claude/settings.json").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: zaiConfigPathInput) { _, newValue in
                            UserDefaultsProviderSettingsRepository.shared.setZaiConfigPath(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("AUTH TOKEN ENV VAR (FALLBACK)")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $glmAuthEnvVarInput, prompt: Text("GLM_AUTH_TOKEN").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: glmAuthEnvVarInput) { _, newValue in
                            UserDefaultsProviderSettingsRepository.shared.setGlmAuthEnvVar(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave both empty to use default path with no env var fallback")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.6, blue: 0.9),
                                    Color(red: 0.15, green: 0.45, blue: 0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Z.ai / GLM Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Authentication fallback settings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

                Spacer()
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    zaiConfigExpanded.toggle()
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
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Bedrock Config Card

    private var bedrockConfigCard: some View {
        DisclosureGroup(isExpanded: $bedrockConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                // AWS Profile Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("AWS PROFILE NAME")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $awsProfileNameInput, prompt: Text("default").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: awsProfileNameInput) { _, newValue in
                            UserDefaultsProviderSettingsRepository.shared.setAWSProfileName(newValue)
                        }
                }

                // Regions
                VStack(alignment: .leading, spacing: 6) {
                    Text("REGIONS (COMMA-SEPARATED)")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $bedrockRegionsInput, prompt: Text("us-east-1, us-west-2").foregroundStyle(theme.textTertiary))
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
                        .onChange(of: bedrockRegionsInput) { _, newValue in
                            let regions = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            UserDefaultsProviderSettingsRepository.shared.setBedrockRegions(regions)
                        }
                }

                // Daily Budget
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAILY BUDGET (USD, OPTIONAL)")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)

                        TextField("", text: $bedrockDailyBudgetInput, prompt: Text("50.00").foregroundStyle(theme.textTertiary))
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
                            .onChange(of: bedrockDailyBudgetInput) { _, newValue in
                                if newValue.isEmpty {
                                    UserDefaultsProviderSettingsRepository.shared.setBedrockDailyBudget(nil)
                                } else if let value = Decimal(string: newValue) {
                                    UserDefaultsProviderSettingsRepository.shared.setBedrockDailyBudget(value)
                                }
                            }
                    }
                }

                // Help text
                VStack(alignment: .leading, spacing: 4) {
                    Text("AWS credentials are loaded from your configured profile.")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)

                    Text("Configure with: aws configure --profile <name>")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                // Link to AWS console
                Link(destination: URL(string: "https://console.aws.amazon.com/bedrock/home")!) {
                    HStack(spacing: 3) {
                        Text("Open Bedrock Console")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                    Color(red: 0.9, green: 0.45, blue: 0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AWS Bedrock Configuration")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("CloudWatch usage tracking")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bedrockConfigExpanded.toggle()
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
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Updates Card

#if ENABLE_SPARKLE
    private var updatesCard: some View {
        DisclosureGroup(isExpanded: $updatesExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Show different content based on updater availability
                if sparkleUpdater?.isAvailable == true {
                    // Check for Updates Button
                    Button {
                        sparkleUpdater?.checkForUpdates()
                    } label: {
                        HStack(spacing: 6) {
                            if sparkleUpdater?.isCheckingForUpdates == true {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }

                            Text(sparkleUpdater?.isCheckingForUpdates == true ? "Checking..." : "Check for Updates")
                                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.3, green: 0.7, blue: 0.4),
                                            Color(red: 0.2, green: 0.55, blue: 0.35)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sparkleUpdater?.canCheckForUpdates != true || sparkleUpdater?.isCheckingForUpdates == true)
                    .opacity(sparkleUpdater?.canCheckForUpdates == true ? 1 : 0.6)

                    // Last check info
                    if let lastCheck = sparkleUpdater?.lastUpdateCheckDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 8))

                            Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(theme.textTertiary)
                    }

                    // Auto updates toggle
                    HStack {
                        Text("Check automatically")
                            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { sparkleUpdater?.automaticallyChecksForUpdates ?? true },
                            set: { sparkleUpdater?.automaticallyChecksForUpdates = $0 }
                        ))
                        .toggleStyle(.switch)
                        .tint(theme.accentPrimary)
                        .scaleEffect(0.8)
                        .labelsHidden()
                    }

                    // Beta updates toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include beta versions")
                                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                                .foregroundStyle(theme.textPrimary)

                            Text("Get early access to new features")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                                .foregroundStyle(theme.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.receiveBetaUpdates)
                            .toggleStyle(.switch)
                            .tint(theme.accentPrimary)
                            .scaleEffect(0.8)
                            .labelsHidden()
                    }
                } else {
                    // Debug mode message
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 10))
                        Text("Updates unavailable in debug builds")
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    }
                    .foregroundStyle(theme.textTertiary)
                }
            }
        } label: {
            updatesHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        updatesExpanded.toggle()
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
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var updatesHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.7, blue: 0.4),
                                Color(red: 0.2, green: 0.55, blue: 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Updates")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Version \(appVersion)")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    #endif

    // MARK: - App Info (available for both Updates card and About card)

    /// The app version from the bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// The app build number from the bundle
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Logs Card

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.5, green: 0.5, blue: 0.6),
                                    Color(red: 0.4, green: 0.4, blue: 0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Logs")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("View application logs")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            // Open Logs Button
            Button {
                FileLogger.shared.openCurrentLogFile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11, weight: .semibold))

                    Text("Open Log File")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.5, green: 0.5, blue: 0.6),
                                    Color(red: 0.4, green: 0.4, blue: 0.5)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)

            // Help text
            Text("Opens ClaudeBar.log in TextEdit")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - About Card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(theme.accentGradient)
                        .frame(width: 32, height: 32)

                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("About")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text("Version \(appVersion) (\(appBuild))")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()
            }

            // GitHub Link
            Link(destination: URL(string: "https://github.com/tddworks/claudebar")!) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))

                    Text("View on GitHub")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.2, blue: 0.25),
                                    Color(red: 0.15, green: 0.15, blue: 0.2)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)

            // Help text
            Text("Report issues or contribute on GitHub")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Background Sync Card

    private var backgroundSyncCard: some View {
        DisclosureGroup(isExpanded: $backgroundSyncExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                // Interval picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("SYNC INTERVAL")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Picker("", selection: $settings.backgroundSyncInterval) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!settings.backgroundSyncEnabled)
                }

                // Help text
                Text("Sync usage data in the background so it's always fresh when you check.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
            .opacity(settings.backgroundSyncEnabled ? 1 : 0.6)
        } label: {
            backgroundSyncHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        backgroundSyncExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    private var backgroundSyncHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.3, green: 0.6, blue: 0.9),
                                Color(red: 0.2, green: 0.45, blue: 0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Background Sync")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Keep data fresh automatically")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $settings.backgroundSyncEnabled)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings = false
                }
            } label: {
                Text("Done")
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(theme.accentGradient)
                            .shadow(color: theme.accentSecondary.opacity(0.25), radius: 6, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func saveToken() {
        saveError = nil
        saveSuccess = false

        copilotProvider?.saveToken(copilotTokenInput)
        copilotTokenInput = ""
        saveSuccess = true

        // Trigger refresh for the Copilot provider if enabled
        if let provider = copilotProvider, provider.isEnabled {
            Task {
                try? await provider.refresh()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveSuccess = false
        }
    }

    private func deleteToken() {
        copilotProvider?.deleteCredentials()
        saveError = nil
    }

    private func testCopilotConnection() async {
        isTestingCopilot = true
        copilotTestResult = nil

        // Save current inputs
        UserDefaultsProviderSettingsRepository.shared.setCopilotAuthEnvVar(copilotAuthEnvVarInput)
        if !copilotTokenInput.isEmpty {
            AppLog.credentials.info("Saving Copilot token for connection test")
            copilotProvider?.saveToken(copilotTokenInput)
            copilotTokenInput = ""
        }

        // Try to refresh the copilot provider
        AppLog.credentials.info("Testing Copilot connection via provider refresh")
        await monitor.refresh(providerId: ProviderID.copilot)

        // Check if there's an error after refresh
        if let error = monitor.provider(for: ProviderID.copilot)?.lastError {
            AppLog.credentials.error("Copilot connection test failed: \(error.localizedDescription)")
            copilotTestResult = "Failed: \(error.localizedDescription)"
        } else {
            AppLog.credentials.info("Copilot connection test succeeded")
            copilotTestResult = "Success: Connection verified"
        }

        isTestingCopilot = false
    }
}

// MARK: - Theme Option Button

struct ThemeOptionButton: View {
    let mode: ThemeMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Icon with themed styling
                ZStack {
                    Circle()
                        .fill(iconBackgroundGradient)
                        .frame(width: 28, height: 28)

                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(mode == .cli ? Color.black : .white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.displayName)
                        .font(.system(size: 11, weight: .medium, design: mode == .cli ? .monospaced : theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    if mode == .christmas {
                        Text("Festive")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(ChristmasTheme().accentPrimary)
                    } else if mode == .cli {
                        Text("Terminal")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(CLITheme().accentPrimary)
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.statusHealthy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: mode == .cli ? 6 : 10)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.15) : (isHovering ? theme.hoverOverlay : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: mode == .cli ? 6 : 10)
                            .stroke(isSelected ? theme.accentPrimary : theme.glassBorder.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var iconBackgroundGradient: LinearGradient {
        switch mode {
        case .light:
            return LinearGradient(colors: [Color.orange, Color.yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dark:
            return LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .system:
            return LinearGradient(colors: [Color.gray, Color.secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cli:
            return CLITheme().accentGradient
        case .christmas:
            return ChristmasTheme().accentGradient
        }
    }
}

// MARK: - Preview

#Preview("Settings - Dark") {
    ZStack {
        DarkTheme().backgroundGradient
        SettingsContentView(showSettings: .constant(true), monitor: QuotaMonitor(providers: AIProviders(providers: [])))
    }
    .appThemeProvider(themeModeId: "dark")
    .frame(width: 380, height: 420)
}

#Preview("Settings - Light") {
    ZStack {
        LightTheme().backgroundGradient
        SettingsContentView(showSettings: .constant(true), monitor: QuotaMonitor(providers: AIProviders(providers: [])))
    }
    .appThemeProvider(themeModeId: "light")
    .frame(width: 380, height: 420)
}
