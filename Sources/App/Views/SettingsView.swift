import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// Inline settings content view that fits within the menu bar popup.
struct SettingsContentView: View {
    @Binding var showSettings: Bool
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var settings = AppSettings.shared

    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif

    // Token input state
    @State private var copilotTokenInput: String = ""
    @State private var showToken: Bool = false
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false

    // Budget input state
    @State private var budgetInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    themeCard
                    claudeBudgetCard
                    copilotCard
                    zaiDemoCard
                    #if ENABLE_SPARKLE
                    updatesCard
                    #endif
                    logsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .onAppear {
            // Initialize budget input with current value
            if settings.claudeApiBudget > 0 {
                budgetInput = String(describing: settings.claudeApiBudget)
            }
        }
    }

    // MARK: - Theme Card

    @Environment(\.isChristmasTheme) private var isChristmas

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
                        .fill(
                            isChristmas
                                ? AppTheme.christmasAccentGradient
                                : AppTheme.accentGradient(for: colorScheme)
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: currentThemeMode.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Appearance")
                        .font(AppTheme.titleFont(size: 14))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))

                    Text("Choose your theme")
                        .font(AppTheme.captionFont(size: 10))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
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
                        isSelected: currentThemeMode == mode,
                        isChristmas: isChristmas
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
            RoundedRectangle(cornerRadius: 14)
                .fill(isChristmas ? AppTheme.christmasCardGradient : AppTheme.cardGradient(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: isChristmas
                                    ? [AppTheme.christmasGold.opacity(0.4), AppTheme.christmasGold.opacity(0.2)]
                                    : [
                                        colorScheme == .dark ? Color.white.opacity(0.25) : AppTheme.purpleVibrant(for: colorScheme).opacity(0.18),
                                        colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Back button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Back")
                        .font(AppTheme.bodyFont(size: 11))
                }
                .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppTheme.glassBackground(for: colorScheme))
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.glassBorder(for: colorScheme), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Settings")
                .font(AppTheme.titleFont(size: 16))
                .foregroundStyle(AppTheme.textPrimary(for: colorScheme))

            Spacer()

            // Invisible placeholder to balance the header
            Color.clear
                .frame(width: 60, height: 1)
        }
    }

    // MARK: - Claude Budget Card

    private var claudeBudgetCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with icon, title, toggle
            claudeBudgetHeader

            // Expandable content
            if settings.claudeApiBudgetEnabled {
                Divider()
                    .background(AppTheme.glassBorder(for: colorScheme))
                    .padding(.vertical, 12)

                claudeBudgetForm
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.25) : AppTheme.purpleVibrant(for: colorScheme).opacity(0.18),
                                    colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
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
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))

                Text("Cost threshold warnings")
                    .font(AppTheme.captionFont(size: 10))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
            }

            Spacer()

            Toggle("", isOn: $settings.claudeApiBudgetEnabled)
                .toggleStyle(.switch)
                .tint(AppTheme.purpleVibrant(for: colorScheme))
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    private var claudeBudgetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Budget Amount
            VStack(alignment: .leading, spacing: 6) {
                Text("MONTHLY BUDGET (USD)")
                    .font(AppTheme.captionFont(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Text("$")
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textSecondary(for: colorScheme))

                    TextField("", text: $budgetInput, prompt: Text("10.00").foregroundStyle(AppTheme.textTertiary(for: colorScheme)))
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppTheme.glassBorder(for: colorScheme), lineWidth: 1)
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
                    .font(AppTheme.captionFont(size: 9))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))

                Text("Only applies to Claude API accounts, not Claude Max.")
                    .font(AppTheme.captionFont(size: 9))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
            }
        }
    }

    // MARK: - Copilot Card

    private var copilotCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with icon, title, toggle
            copilotHeader

            // Expandable content
            if settings.copilotEnabled {
                Divider()
                    .background(AppTheme.glassBorder(for: colorScheme))
                    .padding(.vertical, 12)

                copilotForm
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.25) : AppTheme.purpleVibrant(for: colorScheme).opacity(0.18),
                                    colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
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
                Text("GitHub Copilot")
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))

                Text("Premium usage tracking")
                    .font(AppTheme.captionFont(size: 10))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
            }

            Spacer()

            Toggle("", isOn: $settings.copilotEnabled)
                .toggleStyle(.switch)
                .tint(AppTheme.purpleVibrant(for: colorScheme))
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    private var copilotForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // GitHub Username
            VStack(alignment: .leading, spacing: 6) {
                Text("GITHUB USERNAME")
                    .font(AppTheme.captionFont(size: 9))
                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                    .tracking(0.5)

                TextField("", text: $settings.githubUsername, prompt: Text("username").foregroundStyle(AppTheme.textTertiary(for: colorScheme)))
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.glassBorder(for: colorScheme), lineWidth: 1)
                            )
                    )
            }

            // Personal Access Token
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PERSONAL ACCESS TOKEN")
                        .font(AppTheme.captionFont(size: 9))
                        .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                        .tracking(0.5)

                    Spacer()

                    if settings.hasCopilotToken {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("Configured")
                                .font(AppTheme.captionFont(size: 9))
                        }
                        .foregroundStyle(AppTheme.statusHealthy(for: colorScheme))
                    }
                }

                HStack(spacing: 6) {
                    // Token input field
                    Group {
                        if showToken {
                            TextField("", text: $copilotTokenInput, prompt: Text("ghp_xxxx...").foregroundStyle(AppTheme.textTertiary(for: colorScheme)))
                        } else {
                            SecureField("", text: $copilotTokenInput, prompt: Text("ghp_xxxx...").foregroundStyle(AppTheme.textTertiary(for: colorScheme)))
                        }
                    }
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppTheme.glassBorder(for: colorScheme), lineWidth: 1)
                            )
                    )

                    // Eye button
                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(AppTheme.glassBackground(for: colorScheme))
                            )
                    }
                    .buttonStyle(.plain)

                    // Save button
                    Button {
                        saveToken()
                    } label: {
                        Text("Save")
                            .font(AppTheme.bodyFont(size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(AppTheme.accentGradient(for: colorScheme))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(copilotTokenInput.isEmpty)
                    .opacity(copilotTokenInput.isEmpty ? 0.5 : 1)
                }

                // Status messages
                if let error = saveError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(error)
                            .font(AppTheme.captionFont(size: 9))
                    }
                    .foregroundStyle(AppTheme.statusCritical(for: colorScheme))
                } else if saveSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("Token saved!")
                            .font(AppTheme.captionFont(size: 9))
                    }
                    .foregroundStyle(AppTheme.statusHealthy(for: colorScheme))
                }
            }

            // Help text and link
            VStack(alignment: .leading, spacing: 4) {
                Text("Create a fine-grained PAT with 'Plan: read' permission")
                    .font(AppTheme.captionFont(size: 9))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))

                Link(destination: URL(string: "https://github.com/settings/tokens?type=beta")!) {
                    HStack(spacing: 3) {
                        Text("Create token on GitHub")
                            .font(AppTheme.captionFont(size: 9))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.purpleVibrant(for: colorScheme))
                }
            }

            // Delete token
            if settings.hasCopilotToken {
                Button {
                    deleteToken()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9))
                        Text("Remove Token")
                            .font(AppTheme.captionFont(size: 9))
                    }
                    .foregroundStyle(AppTheme.statusCritical(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Z.ai Demo Card

    private var zaiDemoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with icon, title, toggle
            HStack(spacing: 10) {
                // Provider icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.6, blue: 0.9),
                                    Color(red: 0.1, green: 0.4, blue: 0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Z.ai Demo Mode")
                        .font(AppTheme.titleFont(size: 14))
                        .foregroundStyle(AppTheme.textPrimary(for: colorScheme))

                    Text("Preview UI with mock data")
                        .font(AppTheme.captionFont(size: 10))
                        .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
                }

                Spacer()

                Toggle("", isOn: $settings.zaiDemoMode)
                    .toggleStyle(.switch)
                    .tint(AppTheme.purpleVibrant(for: colorScheme))
                    .scaleEffect(0.8)
                    .labelsHidden()
            }

            // Help text
            Text("Enable to test Z.ai provider without credentials. Restart app to apply.")
                .font(AppTheme.captionFont(size: 9))
                .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.cardGradient(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    colorScheme == .dark ? Color.white.opacity(0.25) : AppTheme.purpleVibrant(for: colorScheme).opacity(0.18),
                                    colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
                                ],
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
        VStack(alignment: .leading, spacing: 12) {
            // Header
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
                        .font(AppTheme.titleFont(size: 14))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))

                    Text("Version \(appVersion)")
                        .font(AppTheme.captionFont(size: 10))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
                }

                Spacer()
            }

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
                            .font(AppTheme.bodyFont(size: 11))
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
                            .font(AppTheme.captionFont(size: 9))
                    }
                    .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
                }

                // Auto updates toggle
                HStack {
                    Text("Check automatically")
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { sparkleUpdater?.automaticallyChecksForUpdates ?? true },
                        set: { sparkleUpdater?.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppTheme.purpleVibrant(for: colorScheme))
                    .scaleEffect(0.8)
                    .labelsHidden()
                }

                // Beta updates toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include beta versions")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))

                        Text("Get early access to new features")
                            .font(AppTheme.captionFont(size: 9))
                            .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
                    }

                    Spacer()

                    Toggle("", isOn: $settings.receiveBetaUpdates)
                        .toggleStyle(.switch)
                        .tint(AppTheme.purpleVibrant(for: colorScheme))
                        .scaleEffect(0.8)
                        .labelsHidden()
                }
            } else {
                // Debug mode message
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 10))
                    Text("Updates unavailable in debug builds")
                        .font(AppTheme.captionFont(size: 10))
                }
                .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isChristmas ? AppTheme.christmasCardGradient : AppTheme.cardGradient(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: isChristmas
                                    ? [AppTheme.christmasGold.opacity(0.4), AppTheme.christmasGold.opacity(0.2)]
                                    : [
                                        colorScheme == .dark ? Color.white.opacity(0.25) : AppTheme.purpleVibrant(for: colorScheme).opacity(0.18),
                                        colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    /// The app version from the bundle
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    #endif

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
                        .font(AppTheme.titleFont(size: 14))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))

                    Text("View application logs")
                        .font(AppTheme.captionFont(size: 10))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
                }

                Spacer()
            }

            // Open Logs Button
            Button {
                AppLog.openLogsDirectory()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))

                    Text("Open Logs Folder")
                        .font(AppTheme.bodyFont(size: 11))
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
            Text("Logs are stored at ~/Library/Logs/ClaudeBar/")
                .font(AppTheme.captionFont(size: 9))
                .foregroundStyle(isChristmas ? AppTheme.christmasTextTertiary : AppTheme.textTertiary(for: colorScheme))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isChristmas ? AppTheme.christmasCardGradient : AppTheme.cardGradient(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: isChristmas
                                    ? [AppTheme.christmasGold.opacity(0.4), AppTheme.christmasGold.opacity(0.2)]
                                    : [
                                        colorScheme == .dark ? Color.white.opacity(0.25) : AppTheme.purpleVibrant(for: colorScheme).opacity(0.18),
                                        colorScheme == .dark ? Color.white.opacity(0.08) : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
                                    ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
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
                    .font(AppTheme.bodyFont(size: 11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(AppTheme.accentGradient(for: colorScheme))
                            .shadow(color: AppTheme.pinkHot(for: colorScheme).opacity(0.25), radius: 6, y: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    private func saveToken() {
        saveError = nil
        saveSuccess = false

        settings.saveCopilotToken(copilotTokenInput)
        copilotTokenInput = ""
        saveSuccess = true

        // Add Copilot provider if enabled and not already present
        if settings.copilotEnabled {
            let copilotProvider = CopilotProvider(probe: CopilotUsageProbe())
            appState.addProvider(copilotProvider)

            // Trigger refresh for the new provider
            Task {
                try? await copilotProvider.refresh()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveSuccess = false
        }
    }

    private func deleteToken() {
        settings.deleteCopilotToken()
        saveError = nil
        appState.removeProvider(id: "copilot")
    }
}

// MARK: - Theme Option Button

struct ThemeOptionButton: View {
    let mode: ThemeMode
    let isSelected: Bool
    let isChristmas: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Icon with festive styling for Christmas
                ZStack {
                    Circle()
                        .fill(iconBackgroundGradient)
                        .frame(width: 28, height: 28)

                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.displayName)
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(textColor)

                    if mode == .christmas {
                        Text("Festive")
                            .font(AppTheme.captionFont(size: 8))
                            .foregroundStyle(AppTheme.christmasGold)
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(checkmarkColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
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
            return LinearGradient(
                colors: [Color.orange, Color.yellow],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dark:
            return LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .system:
            return LinearGradient(
                colors: [Color.gray, Color.secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .christmas:
            return AppTheme.christmasAccentGradient
        }
    }

    private var textColor: Color {
        if isChristmas {
            return AppTheme.christmasTextPrimary
        }
        return AppTheme.textPrimary(for: colorScheme)
    }

    private var checkmarkColor: Color {
        if mode == .christmas || isChristmas {
            return AppTheme.christmasGold
        }
        return AppTheme.statusHealthy(for: colorScheme)
    }

    private var backgroundColor: Color {
        if isSelected {
            if mode == .christmas || isChristmas {
                return AppTheme.christmasGold.opacity(0.15)
            }
            return AppTheme.purpleVibrant(for: colorScheme).opacity(0.15)
        }
        if isHovering {
            return AppTheme.glassBackground(for: colorScheme)
        }
        return Color.clear
    }

    private var borderColor: Color {
        if isSelected {
            if mode == .christmas || isChristmas {
                return AppTheme.christmasGold
            }
            return AppTheme.purpleVibrant(for: colorScheme)
        }
        return AppTheme.glassBorder(for: colorScheme).opacity(0.5)
    }
}

// MARK: - Preview

#Preview("Settings - Dark") {
    ZStack {
        AppTheme.backgroundGradient(for: .dark)
        SettingsContentView(showSettings: .constant(true), appState: AppState())
    }
    .frame(width: 380, height: 420)
    .preferredColorScheme(.dark)
}

#Preview("Settings - Light") {
    ZStack {
        AppTheme.backgroundGradient(for: .light)
        SettingsContentView(showSettings: .constant(true), appState: AppState())
    }
    .frame(width: 380, height: 420)
    .preferredColorScheme(.light)
}
