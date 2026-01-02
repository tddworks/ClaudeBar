import SwiftUI
import ClaudeBarShared
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

// Type aliases to disambiguate KMP types from Swift Domain types
typealias KmpQuotaMonitor = ClaudeBarShared.QuotaMonitor
typealias KmpQuotaStatus = ClaudeBarShared.QuotaStatus
typealias KmpAIProvider = ClaudeBarShared.AIProvider
typealias KmpProviderSettingsRepository = ClaudeBarShared.ProviderSettingsRepository
typealias KmpCredentialRepository = ClaudeBarShared.CredentialRepository
typealias KmpCLIExecutor = ClaudeBarShared.CLIExecutor
typealias KmpUsageSnapshot = ClaudeBarShared.UsageSnapshot

// MARK: - Build Instructions
// 1. Build KMP framework: cd shared && ./gradlew :darwin:linkReleaseFrameworkMacosArm64
// 2. Regenerate project: tuist generate
// 3. Swap @main: uncomment below, comment in ClaudeBarApp.swift

/// Alternative app entry point using KMP shared domain layer.
/// Uses QuotaMonitor directly with SKIE's StateFlow support.
@main
struct ClaudeBarAppKmp: App {
    let monitor: KmpQuotaMonitor
    @State private var overallStatus: KmpQuotaStatus = .healthy
    @State private var settings = AppSettings.shared

    #if ENABLE_SPARKLE
    @State private var sparkleUpdater = SparkleUpdater()
    #endif

    init() {
        print("ClaudeBarAppKmp initializing...")

        let settingsRepository = SwiftProviderSettingsRepository()
        let credentialRepository = SwiftCredentialRepository()
        let cliExecutor = SwiftCLIExecutor()

        self.monitor = ClaudeBarShared_.shared.createQuotaMonitor(
            settingsRepository: settingsRepository,
            credentialRepository: credentialRepository,
            cliExecutor: cliExecutor,
            alerter: nil
        )
        print("Created QuotaMonitor with \(monitor.allProviders.count) providers")
    }

    private var currentThemeMode: ThemeMode {
        ThemeMode(rawValue: settings.themeMode) ?? .system
    }

    var body: some Scene {
        MenuBarExtra {
            #if ENABLE_SPARKLE
            KmpMenuContentView(monitor: monitor)
                .themeProvider(currentThemeMode)
                .environment(\.sparkleUpdater, sparkleUpdater)
            #else
            KmpMenuContentView(monitor: monitor)
                .themeProvider(currentThemeMode)
            #endif
        } label: {
            KmpStatusBarIcon(status: overallStatus, isChristmas: currentThemeMode == .christmas)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Swift Implementations of KMP Protocols

/// Swift implementation of ProviderSettingsRepository using UserDefaults
final class SwiftProviderSettingsRepository: KmpProviderSettingsRepository {
    private let defaults = UserDefaults.standard
    private let keyPrefix = "provider.enabled."

    func isEnabled(forProvider providerId: String, defaultValue: Bool) -> Bool {
        let key = keyPrefix + providerId
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    func setEnabled(enabled: Bool, forProvider providerId: String) {
        defaults.set(enabled, forKey: keyPrefix + providerId)
    }
}

/// Swift implementation of CredentialRepository using UserDefaults
final class SwiftCredentialRepository: KmpCredentialRepository {
    private let defaults = UserDefaults.standard
    private let keyPrefix = "credential."

    func delete(forKey key: String) {
        defaults.removeObject(forKey: keyPrefix + key)
    }

    func exists(forKey key: String) -> Bool {
        defaults.object(forKey: keyPrefix + key) != nil
    }

    func get(forKey key: String) -> String? {
        defaults.string(forKey: keyPrefix + key)
    }

    func save(value: String, forKey key: String) {
        defaults.set(value, forKey: keyPrefix + key)
    }
}

/// Swift implementation of CLIExecutor using async/await (SKIE compatible)
final class SwiftCLIExecutor: NSObject, KmpCLIExecutor {
    private let executor = DefaultCLIExecutor()

    func locate(binary: String) -> String? {
        executor.locate(binary)
    }

    // SKIE: Override __execute with async throws
    func __execute(
        binary: String,
        args: [String],
        input: String?,
        timeout: Int64,
        workingDirectory: String?,
        autoResponses: [String: String]
    ) async throws -> ClaudeBarShared.CLIResult {
        let (output, exitCode) = try await Task.detached { [executor] in
                 let result = try executor.execute(
                     binary: binary,
                     args: args,
                     input: input,
                     timeout: max(10.0, Double(timeout) / 1_000_000_000.0),
                     workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) },
                     autoResponses: autoResponses
                 )
                 return (result.output, Int32(result.exitCode))
             }.value
             return ClaudeBarShared.CLIResult(output: output, exitCode: exitCode)
      
    }
}

// MARK: - KMP Type Extensions

extension KmpQuotaStatus {
    func toSwiftQuotaStatus() -> Domain.QuotaStatus {
        switch self {
        case .healthy: return .healthy
        case .warning: return .warning
        case .critical: return .critical
        case .depleted: return .depleted
        default: return .healthy
        }
    }

    var displayColor: Color {
        toSwiftQuotaStatus().displayColor
    }

    func themeColor(for colorScheme: ColorScheme) -> Color {
        toSwiftQuotaStatus().themeColor(for: colorScheme)
    }

    var badgeText: String {
        toSwiftQuotaStatus().badgeText
    }
}

extension ClaudeBarShared.AccountTier {
    var badgeText: String {
        if self is ClaudeBarShared.AccountTier.ClaudeMax { return "MAX" }
        if self is ClaudeBarShared.AccountTier.ClaudePro { return "PRO" }
        if self is ClaudeBarShared.AccountTier.ClaudeApi { return "API" }
        return ""
    }
}

// MARK: - KMP UI Components (matching ClaudeBarApp design)

/// Status bar icon using KMP QuotaStatus
struct KmpStatusBarIcon: View {
    let status: KmpQuotaStatus
    var isChristmas: Bool = false

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        if isChristmas { return "snowflake" }
        switch status {
        case .depleted: return "chart.bar.xaxis"
        case .critical: return "exclamationmark.triangle.fill"
        case .warning, .healthy: return "chart.bar.fill"
        default: return "chart.bar.fill"
        }
    }

    private var iconColor: Color {
        if isChristmas { return AppTheme.christmasGold }
        return status.displayColor
    }
}

/// Menu content view using QuotaMonitor directly with SKIE StateFlow
struct KmpMenuContentView: View {
    let monitor: KmpQuotaMonitor

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isChristmasTheme) private var isChristmas
    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif

    // Local state - updated via StateFlow observation
    @State private var selectedProviderId: String = "claude"
    @State private var snapshot: KmpUsageSnapshot?
    @State private var isSyncing: Bool = false
    @State private var animateIn = false
    @State private var showSettings = false

    private var selectedProvider: KmpAIProvider? {
        monitor.provider(id: selectedProviderId)
    }

    private var selectedProviderStatus: KmpQuotaStatus {
        snapshot?.overallStatus ?? .healthy
    }

    var body: some View {
        ZStack {
            // Gradient background
            (isChristmas ? AppTheme.christmasBackgroundGradient : AppTheme.backgroundGradient(for: colorScheme))
                .ignoresSafeArea()

            // Background orbs
            if isChristmas {
                ChristmasBackgroundOrbs()
            } else {
                backgroundOrbs
            }

            // Snowfall for Christmas
            if isChristmas {
                SnowfallOverlay(snowflakeCount: 25)
            }

            // Main Content
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                providerPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                VStack(spacing: 12) {
                    metricsContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

                actionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
            await refreshSelectedProvider()
        }
        .task(id: selectedProviderId) {
            // Observe snapshot StateFlow for selected provider
            guard let provider = selectedProvider else { return }
            for await newSnapshot in provider.snapshot {
                self.snapshot = newSnapshot
            }
        }
        .task(id: selectedProviderId) {
            // Observe syncing StateFlow
            guard let provider = selectedProvider else { return }
            for await syncing in provider.isSyncing {
                self.isSyncing = syncing.boolValue
            }
        }
    }

    private func refreshSelectedProvider() async {
        isSyncing = true
        do {
            try await monitor.__refresh(providerId: selectedProviderId)
        } catch {
            print("Refresh failed: \(error)")
        }
    }

    // MARK: - Background Orbs

    private var backgroundOrbs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.violetElectric(for: colorScheme).opacity(colorScheme == .dark ? 0.4 : 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .offset(x: -60, y: -80)
                    .blur(radius: 40)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                AppTheme.pinkHot(for: colorScheme).opacity(colorScheme == .dark ? 0.35 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: geo.size.width - 80, y: geo.size.height - 150)
                    .blur(radius: 30)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Provider Icon
            ZStack {
                ProviderIconView(providerId: selectedProviderId, size: 38)

                if isChristmas {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(AppTheme.christmasGold)
                        .offset(x: 14, y: -14)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedProviderId)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("ClaudeBar")
                        .font(AppTheme.titleFont(size: 18))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))

                    Text("KMP")
                        .font(AppTheme.captionFont(size: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.purpleVibrant(for: colorScheme)))

                    if isChristmas {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.christmasRed)
                    }
                }

                Text(isChristmas ? "Happy Holidays!" : "AI Usage Monitor")
                    .font(AppTheme.captionFont(size: 11))
                    .foregroundStyle(isChristmas ? AppTheme.christmasTextSecondary : AppTheme.textSecondary(for: colorScheme))
            }

            Spacer()

            // Status Badge
            statusBadge
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -10)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            PulsingStatusDot(
                color: selectedProviderStatus.themeColor(for: colorScheme),
                isSyncing: isSyncing
            )

            Text(statusText)
                .font(AppTheme.captionFont(size: 11))
                .foregroundStyle(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(selectedProviderStatus.themeColor(for: colorScheme).opacity(isChristmas ? 0.3 : (colorScheme == .dark ? 0.25 : 0.15)))
                .overlay(
                    Capsule()
                        .stroke(
                            isChristmas
                                ? AppTheme.christmasGold.opacity(0.5)
                                : selectedProviderStatus.themeColor(for: colorScheme).opacity(colorScheme == .dark ? 0.5 : 0.3),
                            lineWidth: 1
                        )
                )
        )
    }

    private var statusText: String {
        if isSyncing { return "Syncing..." }
        return selectedProviderStatus.badgeText
    }

    // MARK: - Provider Pills

    private var providerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(monitor.enabledProviders), id: \.id) { provider in
                    ProviderPill(
                        providerId: provider.id,
                        providerName: provider.name,
                        isSelected: provider.id == selectedProviderId,
                        hasData: provider.snapshot.value != nil
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedProviderId = provider.id
                        }
                    }
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIn)
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if let provider = selectedProvider, let snapshot = provider.snapshot.value {
            VStack(spacing: 12) {
                // Account info card - show if email OR organization is available
                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    kmpAccountCard(displayName: displayName, snapshot: snapshot)
                }

                // Stats Grid
                kmpStatsGrid(snapshot: snapshot)
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if isSyncing {
            LoadingSpinnerView()
        } else {
            kmpEmptyState
        }
    }

    private func kmpAccountCard(displayName: String, snapshot: KmpUsageSnapshot) -> some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(AppTheme.providerGradient(for: selectedProviderId, scheme: colorScheme))
                    .frame(width: 32, height: 32)

                Text(String(displayName.prefix(1)).uppercased())
                    .font(AppTheme.titleFont(size: 14))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(AppTheme.bodyFont(size: 12))
                        .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)

                    // Account tier badge
                    if let accountTier = snapshot.accountTier {
                        Text(accountTier.badgeText)
                            .font(AppTheme.captionFont(size: 8))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.purpleVibrant(for: colorScheme).opacity(0.8)))
                    }
                }
            }

            Spacer()
        }
        .glassCard(cornerRadius: 12, padding: 10)
    }

    @ViewBuilder
    private func kmpStatsGrid(snapshot: KmpUsageSnapshot) -> some View {
        VStack(spacing: 10) {
            if !snapshot.quotas.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(snapshot.quotas.enumerated()), id: \.offset) { index, quota in
                        KmpStatCard(quota: quota, delay: Double(index) * 0.08)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var kmpEmptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.statusWarning(for: colorScheme).opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.statusWarning(for: colorScheme))
            }

            Text("\(selectedProvider?.name ?? selectedProviderId) Unavailable")
                .font(AppTheme.titleFont(size: 14))
                .foregroundStyle(AppTheme.textPrimary(for: colorScheme))

            Text("Install CLI or check configuration")
                .font(AppTheme.captionFont(size: 11))
                .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            // Dashboard Button
            WrappedActionButton(
                icon: "safari.fill",
                label: "Dashboard",
                gradient: isChristmas ? AppTheme.christmasAccentGradient : AppTheme.providerGradient(for: selectedProviderId, scheme: colorScheme),
                isChristmas: isChristmas
            ) {
                if let urlString = selectedProvider?.dashboardURL,
                   let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }

            // Refresh Button
            WrappedActionButton(
                icon: isSyncing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isSyncing ? "Syncing" : "Refresh",
                gradient: isChristmas ? AppTheme.christmasGreenGradient : AppTheme.accentGradient(for: colorScheme),
                isLoading: isSyncing,
                isChristmas: isChristmas
            ) {
                Task { await refreshSelectedProvider() }
            }

            Spacer()

            // Settings Button
            Button {
                showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(isChristmas ? AppTheme.christmasGlassBackground : AppTheme.glassBackground(for: colorScheme))
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextSecondary : AppTheme.textSecondary(for: colorScheme))
                }
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                ZStack {
                    Circle()
                        .fill(isChristmas ? AppTheme.christmasGlassBackground : AppTheme.glassBackground(for: colorScheme))
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextSecondary : AppTheme.textSecondary(for: colorScheme))
                }
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeBar")
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateIn)
    }
}

// MARK: - KMP Stat Card

struct KmpStatCard: View {
    let quota: ClaudeBarShared.UsageQuota
    let delay: Double

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var animateProgress = false

    private var quotaStatus: Domain.QuotaStatus {
        if quota.percentRemaining < 10 { return .depleted }
        if quota.percentRemaining < 25 { return .critical }
        if quota.percentRemaining < 50 { return .warning }
        return .healthy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(quotaStatus.themeColor(for: colorScheme))

                    Text(quota.quotaType.displayName.uppercased())
                        .font(AppTheme.captionFont(size: 8))
                        .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                        .tracking(0.3)
                }

                Spacer(minLength: 4)

                Text(quotaStatus.badgeText)
                    .badge(quotaStatus.themeColor(for: colorScheme))
            }

            // Large percentage
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(quota.percentRemaining))")
                    .font(AppTheme.statFont(size: 32))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                    .contentTransition(.numericText())

                Text("%")
                    .font(AppTheme.titleFont(size: 16))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressTrackColor)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.progressGradient(for: quota.percentRemaining, scheme: colorScheme))
                        .frame(width: animateProgress ? geo.size.width * quota.percentRemaining / 100 : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animateProgress)
                }
            }
            .frame(height: 5)

            // Reset info
            if let resetText = quota.resetText {
                HStack(spacing: 3) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 7))

                    Text(resetText)
                        .font(AppTheme.captionFont(size: 8))
                }
                .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
                .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.cardGradient(for: colorScheme))

                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.clear)
                        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 6, y: 3)
                }

                RoundedRectangle(cornerRadius: 14)
                    .stroke(cardBorderGradient, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            animateProgress = true
        }
    }

    private var progressTrackColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : AppTheme.purpleDeep(for: colorScheme).opacity(0.1)
    }

    private var cardBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                colorScheme == .dark
                    ? Color.white.opacity(isHovering ? 0.35 : 0.25)
                    : AppTheme.purpleVibrant(for: colorScheme).opacity(isHovering ? 0.3 : 0.18),
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : AppTheme.pinkHot(for: colorScheme).opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconName: String {
        switch quota.quotaType {
        case is ClaudeBarShared.QuotaType.Session: return "bolt.fill"
        case is ClaudeBarShared.QuotaType.Weekly: return "calendar.badge.clock"
        case is ClaudeBarShared.QuotaType.ModelSpecific: return "cpu.fill"
        case is ClaudeBarShared.QuotaType.TimeLimit: return "clock.fill"
        default: return "chart.bar.fill"
        }
    }
}

// MARK: - QuotaType Extension

extension ClaudeBarShared.QuotaType {
    var displayName: String {
        switch self {
        case is ClaudeBarShared.QuotaType.Session: return "Session"
        case is ClaudeBarShared.QuotaType.Weekly: return "Weekly"
        case is ClaudeBarShared.QuotaType.ModelSpecific: return "Model"
        case is ClaudeBarShared.QuotaType.TimeLimit: return "Time"
        default: return "Quota"
        }
    }
}

// MARK: - Previews

#Preview("KmpStatusBarIcon") {
    HStack(spacing: 20) {
        KmpStatusBarIcon(status: KmpQuotaStatus.healthy)
        KmpStatusBarIcon(status: KmpQuotaStatus.warning)
        KmpStatusBarIcon(status: KmpQuotaStatus.critical)
        KmpStatusBarIcon(status: KmpQuotaStatus.depleted)
        KmpStatusBarIcon(status: KmpQuotaStatus.healthy, isChristmas: true)
    }
    .padding()
    .background(.black)
}
