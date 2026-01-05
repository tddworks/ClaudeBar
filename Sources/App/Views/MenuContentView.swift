import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// The main menu content view with adaptive light/dark/christmas theme support.
/// Features purple-pink gradients, glassmorphism cards, and bold typography.
/// Christmas theme adds festive colors, snowfall, and holiday orbs.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let quotaAlerter: QuotaAlerter

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isChristmasTheme) private var isChristmas
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
            // Gradient background - Christmas or standard
            (isChristmas ? AppTheme.christmasBackgroundGradient : AppTheme.backgroundGradient(for: colorScheme))
                .ignoresSafeArea()

            // Subtle animated orbs in background - Christmas or standard
            if isChristmas {
                ChristmasBackgroundOrbs()
            } else {
                backgroundOrbs
            }

            // Snowfall overlay for Christmas theme - lots of snow!
            if isChristmas {
                SnowfallOverlay(snowflakeCount: 25)
            }

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

                    // Provider Pills
                    providerPills
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

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
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            // Request alert permission once (after app run loop is active)
            if !hasRequestedNotificationPermission {
                hasRequestedNotificationPermission = true
                let granted = await quotaAlerter.requestPermission()
                AppLog.notifications.info("Alert permission request result: \(granted ? "granted" : "denied")")
            }

            // Show header and tabs immediately
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
            // Then fetch data in background
            await refresh(providerId: selectedProviderId)

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

                // Pink orb
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
            // Custom Provider Icon - changes based on selected provider
            // For Christmas, add festive glow effect
            ZStack {
                ProviderIconView(providerId: selectedProviderId, size: 38)

                // Christmas star sparkle overlay
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

                    // Christmas gift icon - vibrant red
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

    /// Status of the currently selected provider
    private var selectedProviderStatus: QuotaStatus {
        selectedProvider?.snapshot?.overallStatus ?? .healthy
    }

    /// Whether the selected provider is currently syncing
    private var isSelectedProviderSyncing: Bool {
        selectedProvider?.isSyncing ?? false
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            // Animated pulse dot
            PulsingStatusDot(
                color: selectedProviderStatus.themeColor(for: colorScheme),
                isSyncing: isSelectedProviderSyncing
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
        if let provider = selectedProvider, let snapshot = provider.snapshot {
            VStack(spacing: 12) {
                // Account info card - show if email OR organization is available
                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    accountCard(displayName: displayName, snapshot: snapshot)
                }

                // Stats Grid - Wrapped style with large numbers
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

    private func accountCard(displayName: String, snapshot: UsageSnapshot) -> some View {
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
                            .background(
                                Capsule()
                                    .fill(AppTheme.purpleVibrant(for: colorScheme).opacity(0.8))
                            )
                    }
                }

                Text("Updated \(snapshot.ageDescription)")
                    .font(AppTheme.captionFont(size: 10))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
            }

            Spacer()

            // Stale indicator
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.statusWarning(for: colorScheme))
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
                if let url = selectedProvider?.dashboardURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("d")

            // Refresh Button
            let isCurrentlyRefreshing = selectedProvider?.isSyncing == true
            WrappedActionButton(
                icon: isCurrentlyRefreshing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isCurrentlyRefreshing ? "Syncing" : "Refresh",
                gradient: isChristmas
                    ? AppTheme.christmasGreenGradient
                    : AppTheme.accentGradient(for: colorScheme),
                isLoading: isCurrentlyRefreshing,
                isChristmas: isChristmas
            ) {
                Task { await refresh() }
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
                            .fill(
                                isChristmas
                                    ? AppTheme.christmasGoldGradient
                                    : AppTheme.shareGradient(for: colorScheme)
                            )
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
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings = true
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isChristmas ? AppTheme.christmasGlassBackground : AppTheme.glassBackground(for: colorScheme))
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextSecondary : AppTheme.textSecondary(for: colorScheme))

                    // Update available indicator
                    #if ENABLE_SPARKLE
                    if sparkleUpdater?.isUpdateAvailable == true {
                        UpdateBadge(isChristmas: isChristmas)
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
                        .fill(isChristmas ? AppTheme.christmasGlassBackground : AppTheme.glassBackground(for: colorScheme))
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isChristmas ? AppTheme.christmasTextSecondary : AppTheme.textSecondary(for: colorScheme))
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

    /// Refresh the currently selected provider (for button action)
    private func refresh() async {
        await refresh(providerId: selectedProviderId)
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: providerIcon)
                    .font(.system(size: 10, weight: .semibold))

                Text(providerName)
                    .font(AppTheme.bodyFont(size: 11))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(pillForegroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(AppTheme.providerGradient(for: providerId, scheme: colorScheme))
                            .shadow(color: AppTheme.providerColor(for: providerId, scheme: colorScheme).opacity(colorScheme == .dark ? 0.4 : 0.25), radius: 6, y: 2)
                    } else {
                        Capsule()
                            .fill(pillBackgroundColor)
                    }

                    Capsule()
                        .stroke(pillBorderColor, lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var pillForegroundColor: Color {
        if isSelected {
            return .white
        }
        return AppTheme.textPrimary(for: colorScheme)
    }

    private var pillBackgroundColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isHovering ? 0.18 : 0.12)
        } else {
            return Color.white.opacity(isHovering ? 0.95 : 0.85)
        }
    }

    private var pillBorderColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.3) : Color.white.opacity(0.5)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.15)
            : AppTheme.purpleVibrant(for: colorScheme).opacity(0.2)
    }

    private var providerIcon: String {
        AppTheme.providerSymbolIcon(for: providerId)
    }
}

// MARK: - Wrapped Stat Card

struct WrappedStatCard: View {
    let quota: UsageQuota
    let delay: Double

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var animateProgress = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row with icon, type, and badge
            HStack(alignment: .top, spacing: 0) {
                // Left side: icon and type label
                HStack(spacing: 5) {
                    Image(systemName: iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(quota.status.themeColor(for: colorScheme))

                    Text(quota.quotaType.displayName.uppercased())
                        .font(AppTheme.captionFont(size: 8))
                        .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                        .tracking(0.3)
                }

                Spacer(minLength: 4)

                // Status badge - fixed size, won't wrap
                Text(quota.status.badgeText)
                    .badge(quota.status.themeColor(for: colorScheme))
            }

            // Large percentage number
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(quota.percentRemaining))")
                    .font(AppTheme.statFont(size: 32))
                    .foregroundStyle(AppTheme.textPrimary(for: colorScheme))
                    .contentTransition(.numericText())

                Text("%")
                    .font(AppTheme.titleFont(size: 16))
                    .foregroundStyle(AppTheme.textTertiary(for: colorScheme))
            }

            // Progress bar with gradient
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressTrackColor)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.progressGradient(for: quota.percentRemaining, scheme: colorScheme))
                        .frame(width: animateProgress ? geo.size.width * quota.percentRemaining / 100 : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animateProgress)
                }
            }
            .frame(height: 5)

            // Reset info
            if let resetText = quota.resetText ?? quota.resetDescription {
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

                // Light mode shadow
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
        case .session: return "bolt.fill"
        case .weekly: return "calendar.badge.clock"
        case .modelSpecific: return "cpu.fill"
        case .timeLimit: return "clock.fill"
        }
    }
}

// MARK: - Loading Spinner View

struct LoadingSpinnerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSpinning = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(AppTheme.textTertiary(for: colorScheme), lineWidth: 3)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        AppTheme.accentGradient(for: colorScheme),
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
                .font(AppTheme.bodyFont(size: 13))
                .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
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
    var isChristmas: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                        .tint(isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(label)
                    .font(AppTheme.bodyFont(size: 12))
                    .fixedSize()
            }
            .foregroundStyle(buttonForegroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(isHovering ? AnyShapeStyle(gradient) : AnyShapeStyle(buttonBackgroundColor))

                    Capsule()
                        .stroke(buttonBorderColor, lineWidth: 1)
                }
            )
            .shadow(color: isHovering ? shadowColor : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(isLoading)
    }

    private var buttonForegroundColor: Color {
        if isHovering {
            return .white
        }
        return isChristmas ? AppTheme.christmasTextPrimary : AppTheme.textPrimary(for: colorScheme)
    }

    private var buttonBackgroundColor: Color {
        if isChristmas {
            return AppTheme.christmasGlassBackground
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.white.opacity(0.85)
    }

    private var buttonBorderColor: Color {
        if isChristmas {
            return AppTheme.christmasGlassBorder
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.2)
            : AppTheme.purpleVibrant(for: colorScheme).opacity(0.2)
    }

    private var shadowColor: Color {
        if isChristmas {
            return AppTheme.christmasGold.opacity(0.4)
        }
        return AppTheme.coralAccent(for: colorScheme).opacity(colorScheme == .dark ? 0.3 : 0.2)
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
    var isChristmas: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var badgeGradient: LinearGradient {
        if isChristmas {
            return LinearGradient(
                colors: [AppTheme.christmasGold, AppTheme.christmasRed],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                AppTheme.coralAccent(for: colorScheme),
                AppTheme.pinkHot(for: colorScheme)
            ],
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
