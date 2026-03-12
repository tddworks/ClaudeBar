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

    @State private var providersExpanded: Bool = false
    @State private var updatesExpanded: Bool = false
    @State private var backgroundSyncExpanded: Bool = false

    // Hook settings state
    @State private var hooksExpanded: Bool = false
    @State private var hooksEnabled: Bool = false
    @State private var hooksInstalled: Bool = false
    @State private var hookError: String?

    private enum ProviderID {
        static let claude = "claude"
        static let codex = "codex"
        static let copilot = "copilot"
        static let zai = "zai"
        static let bedrock = "bedrock"
        static let kimi = "kimi"
        static let minimax = "minimax"
        static let alibaba = "alibaba"
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

    private var isCodexEnabled: Bool {
        monitor.provider(for: ProviderID.codex)?.isEnabled ?? false
    }

    private var isKimiEnabled: Bool {
        monitor.provider(for: ProviderID.kimi)?.isEnabled ?? false
    }

    private var isMiniMaxEnabled: Bool {
        monitor.provider(for: ProviderID.minimax)?.isEnabled ?? false
    }

    private var isBedrockEnabled: Bool {
        monitor.provider(for: ProviderID.bedrock)?.isEnabled ?? false
    }

    private var isAlibabaEnabled: Bool {
        monitor.provider(for: ProviderID.alibaba)?.isEnabled ?? false
    }

    /// Maximum height for the settings view to ensure it fits on small screens
    private var maxSettingsHeight: CGFloat {
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
                    displayModeCard
                    overviewModeCard
                    providersCard
                    if isClaudeEnabled {
                        ClaudeConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isCodexEnabled {
                        CodexConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isKimiEnabled {
                        KimiConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isMiniMaxEnabled {
                        MiniMaxConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isAlibabaEnabled {
                        AlibabaConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isCopilotEnabled {
                        CopilotConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isZaiEnabled {
                        ZaiConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if isBedrockEnabled {
                        BedrockConfigCard(monitor: monitor)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    backgroundSyncCard
                    hooksCard
                    launchAtLoginCard
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
            hooksEnabled = settings.hook.isHookEnabled()
            hooksInstalled = HookInstaller.isInstalled()
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

    // MARK: - Display Mode Card

    private var displayModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            displayModeHeader
            displayModeToggle
            dailyUsageCardsToggle
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

    private var displayModeHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Quota Display")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Show remaining or used percentage")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var displayModeToggle: some View {
        HStack(spacing: 8) {
            ForEach(UsageDisplayMode.allCases, id: \.rawValue) { mode in
                DisplayModeButton(
                    mode: mode,
                    isSelected: settings.usageDisplayMode == mode
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        settings.usageDisplayMode = mode
                    }
                }
            }
        }
    }

    private var dailyUsageCardsToggle: some View {
        HStack {
            Text("Daily Usage Cards")
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Toggle("", isOn: $settings.showDailyUsageCards)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
    }

    // MARK: - Overview Mode Card

    private var overviewModeCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.id == "cli" ? theme.textPrimary : .white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Overview")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Show all providers at once")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { settings.overviewModeEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.overviewModeEnabled = newValue
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(theme.accentPrimary)
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

    // MARK: - Updates Card

#if ENABLE_SPARKLE
    private var updatesCard: some View {
        DisclosureGroup(isExpanded: $updatesExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if sparkleUpdater?.isAvailable == true {
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

                    if let lastCheck = sparkleUpdater?.lastUpdateCheckDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 8))

                            Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(theme.textTertiary)
                    }

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

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Logs Card

    private var logsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Launch at Login Card

    private var launchAtLoginCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.7, blue: 0.4),
                                Color(red: 0.3, green: 0.55, blue: 0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "power")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Start ClaudeBar when you log in")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
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

    // MARK: - Background Sync Card

    private var backgroundSyncCard: some View {
        DisclosureGroup(isExpanded: $backgroundSyncExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
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

    // MARK: - Hooks Card

    private var hooksCard: some View {
        DisclosureGroup(isExpanded: $hooksExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(hooksInstalled ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(hooksInstalled ? "Hooks installed in ~/.claude/settings.json" : "Hooks not installed")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }

                if let hookError {
                    Text(hookError)
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(.red)
                }

                Text("Track Claude Code sessions in real-time. Shows active session status, subagent activity, and task completion.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        } label: {
            hooksHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hooksExpanded.toggle()
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

    private var hooksHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.7, blue: 0.5),
                                Color(red: 0.25, green: 0.55, blue: 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code Hooks")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Live session tracking")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $hooksEnabled)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
                .onChange(of: hooksEnabled) { _, newValue in
                    hookError = nil
                    do {
                        if newValue {
                            try HookInstaller.install()
                        } else {
                            try HookInstaller.uninstall()
                        }
                        settings.hook.setHookEnabled(newValue)
                        hooksInstalled = HookInstaller.isInstalled()
                        NotificationCenter.default.post(
                            name: .hookSettingsChanged,
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    } catch {
                        hookError = error.localizedDescription
                        hooksEnabled = !newValue
                        AppLog.hooks.error("Hook \(newValue ? "install" : "uninstall") failed: \(error.localizedDescription)")
                    }
                }
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

// MARK: - Display Mode Button

struct DisplayModeButton: View {
    let mode: UsageDisplayMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var iconName: String {
        switch mode {
        case .remaining: "arrow.down.right"
        case .used: "arrow.up.right"
        case .pace: "gauge.with.needle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))

                Text(mode.displayLabel)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(buttonBackground)
            .foregroundStyle(isSelected ? theme.accentPrimary : theme.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? theme.accentPrimary.opacity(0.2) : (isHovering ? theme.hoverOverlay : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
            )
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
