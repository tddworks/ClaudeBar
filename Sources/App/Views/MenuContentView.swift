import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// The main menu content view with adaptive theme support via AppThemeProvider.
/// Uses the pluggable theme system for consistent styling across all themes.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let sessionMonitor: SessionMonitor
    let quotaAlerter: QuotaAlerter
    var onHookSettingsChanged: ((Bool) -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif
    @State private var isHoveringRefresh = false
    @State private var animateIn = false
    @State private var showSettings = false
    @State private var showSharePass = false
    @State private var settings = AppSettings.shared
    @State private var hasRequestedNotificationPermission = false

    /// The currently selected provider ID (from monitor, which is @Observable)
    private var selectedProviderId: String {
        get { monitor.selectedProviderId }
        nonmutating set { monitor.selectedProviderId = newValue }
    }

    /// The currently selected provider
    private var selectedProvider: (any AIProvider)? {
        monitor.selectedProvider
    }

    var body: some View {
        ZStack {
            // Gradient background from theme
            theme.backgroundGradient
                .ignoresSafeArea()

            // Background orbs (if theme supports them)
            if theme.showBackgroundOrbs {
                if theme.id == "christmas" {
                    ChristmasBackgroundOrbs()
                } else {
                    backgroundOrbs
                }
            }

            // Theme overlay (e.g., snowfall for Christmas)
            theme.overlayView

            if showSettings {
                // Settings View
                SettingsContentView(showSettings: $showSettings, monitor: monitor)
            } else {
                // Main Content
                VStack(spacing: 0) {
                    // Header with branding
                    headerView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // Provider Pills (hidden in overview mode)
                    if !settings.overviewModeEnabled {
                        providerPills
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Session Indicator (shown when Claude Code is active)
                    if let session = sessionMonitor.activeSession {
                        SessionIndicatorView(session: session)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Main Content Area - no scroll, dynamic height
                    VStack(spacing: 12) {
                        metricsContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Bottom Action Bar
                    actionBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            // Share Pass Overlay
            if showSharePass, let claudeProvider = selectedProvider as? ClaudeProvider,
               let guestPass = claudeProvider.guestPass {
                SharePassOverlay(pass: guestPass) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSharePass = false
                    }
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: .hookSettingsChanged)) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            onHookSettingsChanged?(enabled)
        }
        .task {
            // Request alert permission once (after app run loop is active)
            if !hasRequestedNotificationPermission {
                hasRequestedNotificationPermission = true
                let granted = await quotaAlerter.requestPermission()
                AppLog.notifications.info("Alert permission request result: \(granted ? "granted" : "denied")")

                // Start background sync on first app launch (only once)
                if settings.backgroundSyncEnabled && !monitor.isMonitoring {
                    startBackgroundSync()
                }
            }

            // Show header and tabs immediately
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
            // Then fetch data in background
            if settings.overviewModeEnabled {
                await refreshAllEnabled()
            } else {
                await refresh(providerId: selectedProviderId)
            }

            // Check for updates when menu opens (no UI unless update found)
            #if ENABLE_SPARKLE
            sparkleUpdater?.checkForUpdatesInBackground()
            #endif
        }
        .onChange(of: selectedProviderId) { _, newProviderId in
            // Refresh when user switches provider
            Task {
                await refresh(providerId: newProviderId)
            }
        }
        .onChange(of: settings.backgroundSyncEnabled) { _, enabled in
            // React to background sync toggle
            if enabled {
                startBackgroundSync()
            } else {
                stopBackgroundSync()
            }
        }
        .onChange(of: settings.backgroundSyncInterval) { _, _ in
            // Restart sync with new interval
            if settings.backgroundSyncEnabled {
                restartBackgroundSync()
            }
        }
    }

    // MARK: - Background Sync Control

    private func startBackgroundSync() {
        let interval = Duration.seconds(settings.backgroundSyncInterval)
        AppLog.monitor.info("Starting background sync (interval: \(settings.backgroundSyncInterval)s)")
        Task {
            let stream = monitor.startMonitoring(interval: interval)
            for await _ in stream {
                // Events handled internally by QuotaMonitor
            }
        }
    }

    private func stopBackgroundSync() {
        AppLog.monitor.info("Stopping background sync")
        monitor.stopMonitoring()
    }

    private func restartBackgroundSync() {
        stopBackgroundSync()
        startBackgroundSync()
    }

    // MARK: - Background Orbs

    private var backgroundOrbs: some View {
        GeometryReader { geo in
            ZStack {
                // Large purple orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.purpleVibrant.opacity(colorScheme == .dark ? 0.4 : 0.15),
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

                // Pink orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.pinkHot.opacity(colorScheme == .dark ? 0.35 : 0.12),
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
            // Custom Provider Icon - shows AppLogo in overview mode, provider icon otherwise
            // Avoid animation on provider icon to prevent constraint update loops in MenuBarExtra
            ZStack {
                if settings.overviewModeEnabled, let logo = NSImage(named: "AppLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(theme.accentPrimary.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: theme.accentPrimary.opacity(0.15), radius: 3, y: 1)
                } else {
                    ProviderIconView(providerId: selectedProviderId, size: 38)
                }

                // Christmas star sparkle overlay
                if theme.id == "christmas" {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accentPrimary)
                        .offset(x: 14, y: -14)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("ClaudeBar")
                        .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    // Christmas gift icon
                    if theme.id == "christmas" {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accentPrimary)
                    }
                }

                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.id == "cli" ? theme.accentPrimary : theme.textSecondary)
            }

            Spacer()

            // Status Badge
            statusBadge
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -10)
    }

    private var headerSubtitle: String {
        switch theme.id {
        case "cli": return "> usage monitor"
        case "christmas": return "Happy Holidays!"
        default: return "AI Usage Monitor"
        }
    }

    /// Status of the currently selected provider
    private var selectedProviderStatus: QuotaStatus {
        selectedProvider?.snapshot?.overallStatus ?? .healthy
    }

    /// Whether the selected provider is currently syncing
    private var isSelectedProviderSyncing: Bool {
        selectedProvider?.isSyncing ?? false
    }

    private var statusBadge: some View {
        let statusColor = theme.statusColor(for: selectedProviderStatus)

        return HStack(spacing: 6) {
            // Animated pulse dot
            PulsingStatusDot(
                color: statusColor,
                isSyncing: isSelectedProviderSyncing
            )

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .fill(theme.glassBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(statusColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var statusText: String {
        if isSelectedProviderSyncing { return "Syncing..." }
        return selectedProviderStatus.badgeText
    }

    /// Help text for settings button, includes update info if available
    private var updateAvailableHelpText: String {
        #if ENABLE_SPARKLE
        if let version = sparkleUpdater?.availableVersion, sparkleUpdater?.isUpdateAvailable == true {
            return "Update available: v\(version)"
        }
        #endif
        return "Settings"
    }

    // MARK: - Provider Pills

    /// Only show enabled providers in the pills
    private var enabledProviders: [any AIProvider] {
        monitor.enabledProviders
    }

    private var providerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(enabledProviders, id: \.id) { provider in
                    ProviderPill(
                        providerId: provider.id,
                        providerName: provider.name,
                        isSelected: provider.id == selectedProviderId,
                        hasData: provider.snapshot != nil
                    ) {
                        // Avoid withAnimation to prevent constraint update loops in MenuBarExtra
                        selectedProviderId = provider.id
                    }
                }
            }
            .background(HorizontalScrollBooster())
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIn)
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if settings.overviewModeEnabled {
            let providers = monitor.enabledProviders
            if providers.isEmpty {
                emptyState
            } else {
                overviewContent(providers: providers)
            }
        } else if let provider = selectedProvider, let snapshot = provider.snapshot {
            VStack(spacing: 12) {
                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    accountCard(displayName: displayName, snapshot: snapshot)
                }
                statsGrid(snapshot: snapshot)
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if selectedProvider?.isSyncing == true {
            loadingState
        } else {
            emptyState
        }
    }

    /// Max height for the overview scroll area (80% of screen or 500pt)
    private var overviewMaxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return min(screenHeight * 0.8, 500)
    }

    private func overviewContent(providers: [any AIProvider]) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        Divider()
                            .background(theme.glassBorder)
                    }
                    providerSection(provider: provider)
                }
            }
        }
        .frame(maxHeight: overviewMaxHeight)
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
    }

    private func providerSection(provider: any AIProvider) -> some View {
        VStack(spacing: 8) {
            providerSectionHeader(provider: provider)

            if let snapshot = provider.snapshot {
                statsGrid(snapshot: snapshot)
            } else if provider.isSyncing {
                LoadingSpinnerView()
            } else {
                compactErrorState(provider: provider)
            }
        }
    }

    private func providerSectionHeader(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            ProviderIconView(providerId: provider.id, size: 20, showGlow: false)

            Text(provider.name)
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            let status = provider.snapshot?.overallStatus ?? .healthy
            Text(provider.isSyncing ? "Syncing..." : status.badgeText)
                .badge(theme.statusColor(for: status))
        }
        .padding(.horizontal, 4)
    }

    private func compactErrorState(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.statusWarning)

            Text(provider.lastError?.localizedDescription ?? "Unavailable")
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }


    private func accountCard(displayName: String, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(ProviderVisualIdentityLookup.gradient(for: selectedProviderId, scheme: colorScheme))
                    .frame(width: 32, height: 32)

                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    // Account tier badge
                    if let accountTier = snapshot.accountTier {
                        Text(accountTier.badgeText)
                            .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.accentPrimary.opacity(0.8))
                            )
                    }
                }

                Text("Updated \(snapshot.ageDescription)")
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // Stale indicator
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.statusWarning)
            }
        }
        .glassCard(cornerRadius: 12, padding: 10)
    }

    @ViewBuilder
    private func statsGrid(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 10) {
            // Show quota cards if quotas exist (Max/Pro accounts)
            if !snapshot.quotas.isEmpty {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(Array(snapshot.quotas.enumerated()), id: \.element.quotaType) { index, quota in
                        WrappedStatCard(quota: quota, delay: Double(index) * 0.08)
                    }
                }
            }

            // Show Extra usage cost card if available (Pro with Extra usage enabled)
            if let costUsage = snapshot.costUsage {
                let budget = settings.claudeApiBudgetEnabled ? settings.claudeApiBudget : nil
                CostStatCard(costUsage: costUsage, budget: budget, delay: Double(snapshot.quotas.count) * 0.08)
            }

            // Show Bedrock usage card if available
            if let bedrockUsage = snapshot.bedrockUsage {
                BedrockUsageCard(usage: bedrockUsage, delay: Double(snapshot.quotas.count) * 0.08)
            }
        }
        .padding(.top, 4)
    }

    private var loadingState: some View {
        LoadingSpinnerView()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.statusWarning.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.statusWarning)
            }

            Text("\(selectedProvider?.name ?? selectedProviderId) Unavailable")
                .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            // Show actual error message if available, otherwise generic message
            Text(selectedProvider?.lastError?.localizedDescription ?? "Install CLI or check configuration")
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
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
                gradient: theme.accentGradient
            ) {
                if let url = selectedProvider?.dashboardURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("d")

            // Refresh Button
            let isCurrentlyRefreshing = settings.overviewModeEnabled
                ? monitor.enabledProviders.contains { $0.isSyncing }
                : selectedProvider?.isSyncing == true
            WrappedActionButton(
                icon: isCurrentlyRefreshing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isCurrentlyRefreshing ? "Syncing" : "Refresh",
                gradient: theme.accentGradient,
                isLoading: isCurrentlyRefreshing
            ) {
                if settings.overviewModeEnabled {
                    Task { await refreshAllEnabled() }
                } else {
                    Task { await refresh(providerId: selectedProviderId) }
                }
            }
            .keyboardShortcut("r")

            Spacer()

            // Share Button (Claude only) - icon only
            if let claudeProvider = selectedProvider as? ClaudeProvider,
               claudeProvider.supportsGuestPasses {
                let isFetchingPasses = claudeProvider.isFetchingPasses
                Button {
                    Task { await fetchAndShowPasses() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.shareGradient)
                            .frame(width: 32, height: 32)

                        if isFetchingPasses {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(.white)
                        } else {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Share Claude Code")
                .keyboardShortcut("s")
            }

            // Settings Button with update indicator
            Button {
                // Avoid window resize animation glitches in MenuBarExtra.
                showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)

                    // Update available indicator
                    #if ENABLE_SPARKLE
                    if sparkleUpdater?.isUpdateAvailable == true {
                        UpdateBadge(accentColor: theme.accentPrimary)
                            .offset(x: 14, y: -14)
                    }
                    #endif
                }
            }
            .buttonStyle(.plain)
            .help(updateAvailableHelpText)
            .keyboardShortcut(",")

            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeBar")
            .keyboardShortcut("q")
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateIn)
    }

    // MARK: - Actions

    /// Refresh all enabled providers concurrently
    private func refreshAllEnabled() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in monitor.enabledProviders {
                group.addTask {
                    guard !provider.isSyncing else { return }
                    do {
                        try await provider.refresh()
                    } catch {
                        // Provider stores error in lastError
                    }
                }
            }
        }
    }

    /// Refresh a specific provider by ID
    private func refresh(providerId: String) async {
        guard let provider = monitor.provider(for: providerId) else {
            return
        }

        // Provider.isSyncing is observable - prevents duplicate refreshes
        guard !provider.isSyncing else { return }

        do {
            try await provider.refresh()
        } catch {
            // Provider stores error in lastError
        }
    }

    /// Fetch guest passes and show the share view
    private func fetchAndShowPasses() async {
        guard let claudeProvider = selectedProvider as? ClaudeProvider else {
            return
        }

        // Prevent duplicate fetches
        guard !claudeProvider.isFetchingPasses else { return }

        do {
            _ = try await claudeProvider.fetchPasses()
            withAnimation(.easeInOut(duration: 0.2)) {
                showSharePass = true
            }
        } catch {
            // Provider stores error in lastError
        }
    }
}

// MARK: - Provider Pill

struct ProviderPill: View {
    let providerId: String
    let providerName: String
    let isSelected: Bool
    let hasData: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: providerIcon)
                    .font(.system(size: 10, weight: .semibold))

                Text(providerName)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? (theme.id == "cli" ? theme.textPrimary : .white) : theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(theme.accentGradient)
                            .shadow(color: theme.accentPrimary.opacity(0.3), radius: 6, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(isHovering ? theme.hoverOverlay : theme.glassBackground)
                    }

                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var providerIcon: String {
        ProviderVisualIdentityLookup.symbolIcon(for: providerId)
    }
}

// MARK: - Wrapped Stat Card

struct WrappedStatCard: View {
    let quota: UsageQuota
    let delay: Double

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false
    @State private var animateProgress = false
    @State private var settings = AppSettings.shared

    private var displayMode: UsageDisplayMode {
        settings.usageDisplayMode
    }

    /// Effective display mode: falls back to .used when pace is unknown
    private var effectiveDisplayMode: UsageDisplayMode {
        if displayMode == .pace && quota.pace == .unknown {
            return .used
        }
        return displayMode
    }

    private var statusColor: Color {
        theme.statusColor(for: quota.status)
    }

    /// The color used for the pace label/number
    private var paceColor: Color {
        quota.pace.displayColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row with icon, type, and badge
            HStack(alignment: .top, spacing: 0) {
                // Left side: icon and type label
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(statusColor)

                    Text(quota.quotaType.displayName.uppercased())
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.3)
                }

                Spacer(minLength: 4)

                // Status badge - pace mode shows pace badge, others show status
                if effectiveDisplayMode == .pace {
                    Text(quota.pace.displayName.uppercased())
                        .badge(paceColor)
                } else {
                    Text(quota.status.badgeText)
                        .badge(statusColor)
                }
            }

            // Large value display with label (end-aligned)
            HStack(alignment: .firstTextBaseline) {
                if let dollarText = quota.formattedDollarRemaining {
                    Text(dollarText)
                        .font(.system(size: 22, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(quota.displayPercent(mode: effectiveDisplayMode)))")
                            .font(.system(size: 32, weight: .bold, design: theme.fontDesign))
                            .foregroundStyle(effectiveDisplayMode == .pace ? paceColor : theme.textPrimary)
                            .contentTransition(.numericText())

                        Text("%")
                            .font(.system(size: 16, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(effectiveDisplayMode == .pace ? paceColor.opacity(0.7) : theme.textTertiary)
                    }
                }

                Spacer()

                Text(quota.isDollarBased ? "remaining" : effectiveDisplayMode.displayLabel)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(effectiveDisplayMode == .pace ? paceColor.opacity(0.8) : theme.textTertiary)
            }

            // Pace insight line
            if effectiveDisplayMode == .pace, let insight = quota.paceInsight {
                HStack(spacing: 3) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 7))
                    Text(insight)
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(paceColor.opacity(0.8))
                .lineLimit(1)
            }

            // Progress bar with gradient and pace tick
            VStack(spacing: 1) {
                GeometryReader { geo in
                    let progressPercent = quota.displayProgressPercent(mode: effectiveDisplayMode)
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressTrack)

                        // Fill (clamp width to 0-100%)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressGradient(for: quota.percentRemaining))
                            .frame(width: animateProgress ? geo.size.width * max(0, min(100, progressPercent)) / 100 : 0)
                            .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animateProgress)
                    }
                }
                .frame(height: 5)

                // Expected pace tick mark
                if let expectedPercent = quota.expectedProgressPercent(mode: effectiveDisplayMode) {
                    GeometryReader { geo in
                        let tickX = geo.size.width * max(0, min(100, expectedPercent)) / 100
                        Path { path in
                            path.move(to: CGPoint(x: tickX - 3, y: 4))
                            path.addLine(to: CGPoint(x: tickX + 3, y: 4))
                            path.addLine(to: CGPoint(x: tickX, y: 0))
                            path.closeSubpath()
                        }
                        .fill(theme.textTertiary)
                        .opacity(animateProgress ? 1 : 0)
                        .animation(.easeIn(duration: 0.3).delay(delay + 0.5), value: animateProgress)
                    }
                    .frame(height: 5)
                }
            }

            // Reset info
            if let resetText = quota.resetTimestampDescription ?? quota.resetText ?? quota.resetDescription {
                HStack(spacing: 3) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 7))

                    Text(resetText)
                        .font(.system(size: 8, weight: .medium, design: theme.fontDesign))
                }
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            animateProgress = true
        }
    }

    private var iconName: String {
        switch quota.quotaType {
        case .session: return "bolt.fill"
        case .weekly: return "calendar.badge.clock"
        case .modelSpecific: return "cpu.fill"
        case .timeLimit: return "clock.fill"
        }
    }
}

// MARK: - Loading Spinner View

struct LoadingSpinnerView: View {
    @Environment(\.appTheme) private var theme
    @State private var isSpinning = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(theme.textTertiary, lineWidth: 3)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        theme.accentGradient,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 1).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
            }

            Text("Fetching usage data...")
                .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
        .onAppear {
            isSpinning = true
        }
    }
}

// MARK: - Wrapped Action Button

struct WrappedActionButton: View {
    let icon: String
    let label: String
    let gradient: LinearGradient
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                        .tint(theme.textPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(label)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .fixedSize()
            }
            .foregroundStyle(isHovering ? .white : theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(isHovering ? AnyShapeStyle(gradient) : AnyShapeStyle(theme.glassBackground))

                    Capsule()
                        .stroke(theme.glassBorder, lineWidth: 1)
                }
            )
            .shadow(color: isHovering ? theme.accentPrimary.opacity(0.3) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(isLoading)
    }
}

// MARK: - Visual Effect Blur (macOS) - Kept for compatibility

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Horizontal Scroll Booster

/// Converts vertical mouse wheel scroll events to horizontal scrolling.
/// Trackpads natively produce horizontal gestures, but mouse scroll wheels only
/// generate vertical deltas — this bridges the gap for horizontal ScrollViews.
///
/// Uses `NSEvent.addLocalMonitorForEvents` to intercept scroll events at the
/// app level before they reach the NSScrollView, which would otherwise ignore
/// vertical deltas in a horizontal-only scroll view.
struct HorizontalScrollBooster: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var monitor: Any?
        weak var view: NSView?

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let scrollView = view.enclosingScrollView else {
                    return event
                }

                // Only act on events over this scroll view
                let point = scrollView.convert(event.locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else {
                    return event
                }

                // Only convert predominantly vertical scrolls
                guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
                    return event
                }

                guard let cgEvent = event.cgEvent?.copy() else {
                    return event
                }

                // Swap vertical → horizontal
                cgEvent.setDoubleValueField(
                    .scrollWheelEventDeltaAxis2,
                    value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                )
                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)

                cgEvent.setIntegerValueField(
                    .scrollWheelEventPointDeltaAxis2,
                    value: cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                )
                cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)

                return NSEvent(cgEvent: cgEvent) ?? event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

// MARK: - Gradient Stops Extension

extension LinearGradient {
    var stops: [Gradient.Stop] {
        // Default empty - used for animation color extraction
        []
    }
}

// MARK: - Pulsing Status Dot

/// A status dot that pulses when syncing, with proper animation lifecycle management.
struct PulsingStatusDot: View {
    let color: Color
    let isSyncing: Bool

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Solid center dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            // Pulsing ring (only visible when syncing)
            if isSyncing {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .scaleEffect(1 + pulsePhase * 0.5)
                    .opacity(1 - pulsePhase)
            } else {
                // Static ring when not syncing
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .opacity(0.5)
            }
        }
        .onChange(of: isSyncing) { _, syncing in
            if syncing {
                startPulsing()
            } else {
                stopPulsing()
            }
        }
        .onAppear {
            if isSyncing {
                startPulsing()
            }
        }
    }

    private func startPulsing() {
        pulsePhase = 0
        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
            pulsePhase = 1
        }
    }

    private func stopPulsing() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulsePhase = 0
        }
    }
}

// MARK: - Update Badge

/// A polished badge indicating an update is available
struct UpdateBadge: View {
    var accentColor: Color = BaseTheme.coralAccent

    private var badgeGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(badgeGradient)
                .frame(width: 18, height: 18)
                .blur(radius: 3)
                .opacity(0.5)

            // Main badge
            Circle()
                .fill(badgeGradient)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Arrow up icon
            Image(systemName: "arrow.up")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Bedrock Usage Card

/// Displays AWS Bedrock usage with cost and per-model breakdown.
struct BedrockUsageCard: View {
    let usage: BedrockUsageSummary
    let delay: Double

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var animateIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with cost
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ProviderVisualIdentityLookup.color(for: "bedrock", scheme: colorScheme))

                        Text("TODAY'S USAGE")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                            .tracking(0.5)
                    }

                    // Large cost number
                    Text(usage.formattedTotalCost)
                        .font(.system(size: 36, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Stats column
                VStack(alignment: .trailing, spacing: 4) {
                    StatPill(icon: "number", value: "\(usage.totalInvocations)", label: "calls")
                    StatPill(icon: "text.word.spacing", value: usage.formattedTotalTokens, label: "tokens")
                }
            }

            // Model breakdown (if multiple models)
            if usage.modelUsages.count > 0 {
                Divider()
                    .background(theme.glassBorder)

                VStack(spacing: 6) {
                    ForEach(usage.modelsBySpend.prefix(3), id: \.model.id) { modelUsage in
                        HStack {
                            Text(modelUsage.model.displayName)
                                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text(modelUsage.formattedCost)
                                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    // Show "and X more" if more than 3 models
                    if usage.modelUsages.count > 3 {
                        Text("and \(usage.modelUsages.count - 3) more...")
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            // Budget progress (if set)
            if let budgetPercent = usage.budgetPercentUsed,
               let budgetFormatted = usage.formattedDailyBudget {
                Divider()
                    .background(theme.glassBorder)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Daily Budget")
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)

                        Spacer()

                        Text("\(Int(min(budgetPercent, 100)))% of \(budgetFormatted)")
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(budgetPercent > 90 ? theme.statusCritical : theme.textPrimary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.progressTrack)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(budgetPercent > 90 ? theme.statusCritical : theme.accentPrimary)
                                .frame(width: geo.size.width * min(CGFloat(budgetPercent) / 100, 1.0))
                        }
                    }
                    .frame(height: 4)
                }
            }

            // Time period
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8))

                Text("Since \(formattedPeriodStart)")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
            }
            .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(delay), value: animateIn)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear { animateIn = true }
    }

    // Cached formatter to avoid recreation overhead
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var formattedPeriodStart: String {
        Self.timeFormatter.string(from: usage.periodStart)
    }
}

// MARK: - Stat Pill (for Bedrock card)

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.textTertiary)

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            Text(label)
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(theme.glassBackground)
        )
    }
}
