import SwiftUI
import Domain
import Infrastructure
import Providers
#if ENABLE_SPARKLE
import Sparkle
#endif

/// The main menu content view with adaptive theme support via AppThemeProvider.
/// Uses the pluggable theme system for consistent styling across all themes.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let sessionMonitor: SessionMonitor
    let quotaAlerter: QuotaAlerter
    let leaderboard: AppLeaderboard
    /// Closes the popover (Escape). The presentation binding lives on the App.
    var onClose: (() -> Void)?
    var onHookSettingsChanged: ((Bool) -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(NewSessions.self) private var newSessions
    /// The user's Text Size choice, injected where the popover is hosted. The
    /// popover's fonts and its width both resolve against this value, so they
    /// can never disagree about how big the popover is.
    @Environment(\.popoverTextSize) private var popoverTextSize
    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif
    @Environment(\.openWindow) private var openWindow
    @State private var isHoveringRefresh = false
    @State private var animateIn = false
    @State private var showSharePass = false

    /// The Claude Code card's height with its padding, taken off the
    /// scroll region's cap so the action bar stays on screen.
    @State private var sessionCardHeight: CGFloat = 0

    /// How many times the popover has opened. The window-style dropdown keeps
    /// this view alive between opens, so the scroll view would keep its offset;
    /// folding this into its identity starts every open at the top.
    @State private var openCount = 0
    @State private var settings = AppSettings.shared
    @State private var hasRequestedNotificationPermission = false
    @State private var pillsOverflow = false
    @State private var pillsContentWidth: CGFloat = 0
    @State private var pillsViewportWidth: CGFloat = 0
    /// Logins hidden by the account chips — the page's filter, never a pause.
    @State private var hiddenAccountIds: Set<String> = []
    /// The page under the pills: All, the Leaderboard, or the selected provider.
    @State private var page: PopoverPage = .provider

    /// Every provider in the lineup as a card, for the All page.
    private var overview: Overview { Overview(monitor) }

    /// The page that can be shown — All needs two providers, the Leaderboard
    /// needs to be on; otherwise the provider.
    private var shownPage: PopoverPage {
        page.shown(allOffered: overview.isOffered, leaderboardOn: leaderboard.membership.isOn)
    }

    private var showsAll: Bool { shownPage == .all }
    private var showsLeaderboard: Bool { shownPage == .leaderboard }

    /// The currently selected provider ID (from monitor, which is @Observable)
    private var selectedProviderId: String {
        get { monitor.selectedProviderId }
        nonmutating set { monitor.selectedProviderId = newValue }
    }

    /// The currently selected provider
    private var selectedLogin: Account? {
        monitor.selectedLogin
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

            // Main Content
            VStack(spacing: 0) {
                // Header with branding
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                providerPills
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16 - scrollTopInset)

                // The Claude Code card (shown while any session is running).
                // Measured, so the scroll region below gives up its height.
                if sessionMonitor.hasActiveSession {
                    SessionsCardView(sessionMonitor: sessionMonitor)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            sessionCardHeight = height
                        }
                } else {
                    Color.clear.frame(height: 0)
                        .onAppear { sessionCardHeight = 0 }
                }

                // Main Content Area — hugs its content, but caps at the
                // screen height and scrolls beyond it (aggregating
                // providers can show a dozen cards; the action bar must
                // never be pushed off-screen).
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        metricsContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, scrollTopInset)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: contentMaxHeight)
                // Recreate the scroll view when the shown content changes
                // or the popover reopens, so a newly selected provider and
                // every open start at the top instead of inheriting the
                // previous scroll offset.
                .id("\(showsAll ? "all" : showsLeaderboard ? "leaderboard" : monitor.selectedProviderId)-\(openCount)")

                // Bottom Action Bar
                actionBar
                    .padding(.horizontal, 16)
                    // A theme's floor: the buttons stand on it, above
                    // its runner's lane.
                    .padding(.bottom, 12 + theme.groundHeight + (theme.runner?.laneHeight ?? 0))
            }
            .overlay(alignment: .bottom) {
                if let runner = theme.runner {
                    GroundRunnerView(
                        runner: runner,
                        status: monitor.selectedProviderStatus,
                        isSyncing: isCurrentlyRefreshing,
                        floorHeight: theme.groundHeight
                    )
                }
            }

            // Share Pass Overlay
            if showSharePass, let guestPass = guestPasses?.pass {
                SharePassOverlay(pass: guestPass) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSharePass = false
                    }
                }
            }

            // Share my rank
            if let card = leaderboard.sharing {
                RankShareOverlay(card: card, monitor: monitor) {
                    withAnimation(.easeInOut(duration: 0.2)) { leaderboard.stopSharing() }
                }
            }

            // Share Pass Error Overlay
            if let guestPasses, let passError = guestPasses.error {
                SharePassErrorOverlay(message: passError.localizedDescription) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        guestPasses.clearError()
                    }
                }
            }
        }
        // Turn off ▾, drawn above the button it opened from, outside the
        // scroll view that would clip it.
        .overlayPreferenceValue(TurnOffAnchorKey.self) { anchor in
            if leaderboard.showsTurnOffMenu, let anchor {
                turnOffMenu(above: anchor)
            }
        }
        .frame(width: popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            openCount += 1
            page = settings.popoverOpensOn.page(onOpening: page)
            leaderboard.dismissOffNotice()
        }
        .background(TouchBarWindowAccessor())
        .background(keyboardShortcuts)
        .background(PopoverKeyWindowAccessor())
        .touchBar {
            ClaudeBarNativeTouchBar(monitor: monitor)
        }
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
            }

            // Show header and tabs immediately
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
            // Then fetch data — passively: opening the popover is not explicit
            // intent, so Codex in RPC mode must not spawn `codex app-server`
            // here before the session was explicitly verified (issue #216).
            // Other providers treat .passive like an interactive refresh.
            if showsAll {
                await refreshAllEnabled(kind: .passive)
            } else {
                await refresh(providerId: selectedProviderId, kind: .passive)
            }

            // Check for updates when menu opens (no UI unless update found)
            #if ENABLE_SPARKLE
            if sparkleUpdater?.automaticallyChecksForUpdates == true {
                sparkleUpdater?.checkForUpdatesInBackground()
            }
            #endif
        }
        .onChange(of: selectedProviderId) { _, newProviderId in
            // Refresh immediately when the user switches provider while the
            // dropdown is open. Periodic background refresh is owned by the
            // app-lifetime loop in ClaudeBarApp, which restarts itself when the
            // selected or menu-bar provider changes.
            Task {
                await refresh(providerId: newProviderId)
            }
        }
        .onChange(of: page) { _, newPage in
            // Opening All reads every provider, as opening the popover on it does.
            if newPage == .all { Task { await refreshAllEnabled(kind: .passive) } }
        }
    }

    /// Upper bound for the scrollable content region — see
    /// `PopoverContentHeight` for the policy and its tests.
    private var contentMaxHeight: CGFloat {
        PopoverContentHeight.maxHeight(
            visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 800,
            overviewMode: showsAll,
            sessionCardHeight: sessionCardHeight
        )
    }

    /// The popover widens with its text size, so a line that fits at one size
    /// still fits at the next instead of truncating — see
    /// `PopoverContentWidth`.
    ///
    /// Read from the environment, like every `popoverFont` in the popover: the
    /// frame and the text must never resolve to different sizes.
    private var popoverWidth: CGFloat {
        popoverTextSize.popoverWidth
    }

    // MARK: - Turn off ▾

    /// The menu's card, just above the button, its right edge set in from
    /// the board card's and the popover's so their outlines don't run into
    /// its own; any click outside it closes it.
    private func turnOffMenu(above anchor: Anchor<CGRect>) -> some View {
        GeometryReader { proxy in
            let button = proxy[anchor]
            let trailing = min(button.maxX - 10, proxy.size.width - 30)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { leaderboard.closeTurnOffMenu() }
                TurnOffMenu(leaderboard: leaderboard) {
                    SettingsRoute.shared.open(.leaderboard)
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .alignmentGuide(.leading) { $0[.trailing] - trailing }
                .alignmentGuide(.top) { $0[.bottom] - (button.minY - 6) }
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    /// Shortcuts with no button of their own: Escape, ⌘0 for All and ⌘1–⌘9
    /// for the provider pills. The action bar's buttons carry theirs directly.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Close", action: handleEscape)
                .keyboardShortcut(.cancelAction)

            Button("All providers") { page = .all }
                .keyboardShortcut("0")

            ForEach(1...9, id: \.self) { position in
                Button("Select provider \(position)") {
                    page = .provider
                    monitor.selectProvider(atPosition: position)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(position))))
            }
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Escape backs out one level: an open overlay first, then the popover.
    private func handleEscape() {
        if leaderboard.showsTurnOffMenu {
            leaderboard.closeTurnOffMenu()
        } else if showSharePass {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSharePass = false
            }
        } else if let guestPasses, guestPasses.error != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                guestPasses.clearError()
            }
        } else {
            onClose?()
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
        VStack(alignment: .leading, spacing: 10) {
            if theme.headerStyle == .scoreLine {
                ScoreLineView(line: scoreLine)
            }
            brandRow
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -10)
    }

    /// The selected tab as a game's score line: its name and status word,
    /// its first quota's coins, the tab's place, the minutes to its reset.
    private var scoreLine: ScoreLine {
        let tabs = monitor.tabs
        if showsAll {
            return ScoreLine(providerName: "All", status: statusText,
                             quotas: overview.tightest.map { [$0] } ?? [], tab: 0)
        }
        let index = tabs.firstIndex { $0.contains(selectedProviderId) } ?? 0
        return ScoreLine(
            providerName: tabs.indices.contains(index) ? settings.shown(tabs[index].name) : "ClaudeBar",
            status: statusText,
            quotas: selectedLogin?.snapshot?.quotas ?? [],
            tab: index + 1
        )
    }

    private var isCurrentlyRefreshing: Bool {
        showsAll
            ? monitor.lineup.contains { $0.isSyncing }
            : selectedLogin?.isSyncing == true
    }

    /// Refresh what's on screen — the selected provider, or every one in
    /// the overview — and the leaderboard.
    private func refreshNow() {
        // An explicit refresh is the moment a user who just installed a
        // CLI expects it to be picked up, so drop the cached lookups
        // instead of waiting for their TTL to lapse.
        BinaryLocator.invalidateCaches()
        Task { await leaderboard.refresh() }
        if showsAll {
            Task { await refreshAllEnabled() }
        } else {
            Task { await refresh(providerId: selectedProviderId) }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 12) {
            // Custom Provider Icon - shows AppLogo on All and on the Leaderboard
            // tab (neither is any one provider's), the provider icon otherwise.
            // Avoid animation on provider icon to prevent constraint update loops in MenuBarExtra
            ZStack {
                if shownPage != .provider, let logo = NSImage(named: "AppLogo") {
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
                        .popoverFont(10)
                        .foregroundStyle(theme.accentPrimary)
                        .offset(x: 14, y: -14)
                }
            }
            // One slot for every tab: a provider icon's glow is drawn 1.3× its size,
            // and without this it made the header taller than the app logo's.
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(settings.popoverTitle.shown)
                        .popoverDisplayFont(18)
                        .lineLimit(1)
                        .foregroundStyle(theme.textPrimary)

                    // Christmas gift icon
                    if theme.id == "christmas" {
                        Image(systemName: "gift.fill")
                            .popoverFont(12)
                            .foregroundStyle(theme.accentPrimary)
                    }
                }

                Text(headerSubtitle)
                    .popoverFont(11, weight: .medium)
                    .foregroundStyle(theme.id == "cli" ? theme.accentPrimary : theme.textSecondary)
            }

            Spacer()

            // Status Badge: the provider's status, or on the Leaderboard tab the
            // leaderboard's own — same pill, so the header never changes height.
            // A score-line header has a ? block there instead, which refreshes
            // too: its status word is in the score line.
            if theme.headerStyle == .scoreLine {
                QuestionBlockButton(isSyncing: isCurrentlyRefreshing, action: refreshNow)
                    .help("Refresh")
            } else if showsLeaderboard {
                leaderboardBadge
            } else {
                statusBadge
            }
        }
    }

    private var headerSubtitle: String {
        theme.tagline ?? "AI Usage Monitor"
    }

    /// What the header pill says — the monitor's word for the selected tab.
    /// A provider that failed to probe reads as "UNAVAILABLE" rather than
    /// borrowing a green "HEALTHY" it has no data for (#259).
    private var selectedProviderBadge: ProviderBadgeState { showsAll ? overview.badge : monitor.selectedBadge }

    private var statusBadge: some View {
        let statusColor = selectedProviderBadge.badgeColor(theme)
        // An outlined theme fills the badge with its status colour, inked —
        // syncing and waiting with a light "in progress" colour, never dark.
        let fill: Color = switch selectedProviderBadge {
        case .syncing, .awaitingData: theme.accentSecondary
        default: statusColor
        }
        // Nothing to say about limits it can't read while its usage shows
        // below: hidden, not removed, so the header keeps its height.
        return headerPill(text: statusText, color: statusColor, fill: fill, pulsing: selectedProviderBadge == .syncing)
            .opacity(selectedProviderBadge.showsBadge ? 1 : 0)
    }

    /// *NOT JOINED · RANKED · UPLOAD FAILED* — the Leaderboard tab's own pill.
    private var leaderboardBadge: some View {
        let membership = leaderboard.membership
        let (text, color): (String, Color) = if !membership.isJoined {
            ("NOT JOINED", theme.accentSecondary)
        } else if leaderboard.uploader.lastError != nil {
            ("UPLOAD FAILED", theme.statusWarning)
        } else {
            ("RANKED", theme.statusHealthy)
        }
        return headerPill(text: text, color: color, fill: color, pulsing: leaderboard.uploader.isUploading)
    }

    /// The header's pill, in the theme's way: a pulse dot and a word.
    private func headerPill(text: String, color statusColor: Color, fill: Color, pulsing: Bool) -> some View {
        let outlined = theme.isOutlined
        return HStack(spacing: 6) {
            // Animated pulse dot
            PulsingStatusDot(
                color: outlined ? theme.textOnStatus : statusColor,
                isSyncing: pulsing
            )

            Text(text)
                .popoverFont(11, weight: outlined ? .heavy : .medium)
                .foregroundStyle(outlined ? theme.textOnStatus : theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .fill(outlined ? fill : theme.glassBackground)
                .themeShadow(theme, scale: 0.5)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(outlined ? theme.glassBorder : statusColor.opacity(0.5),
                                lineWidth: outlined ? theme.cardBorderWidth * 0.8 : 1)
                )
        )
    }

    private var statusText: String {
        selectedProviderBadge.badgeText(in: theme)
    }

    /// Help text for settings button, includes update info if available
    private var updateAvailableHelpText: String {
        #if ENABLE_SPARKLE
        if let version = sparkleUpdater?.availableVersion, sparkleUpdater?.isUpdateAvailable == true {
            return "Update available: v\(version)"
        }
        #endif
        return "Settings (⌘,)"
    }

    // MARK: - Provider Pills

    /// Only show enabled providers in the pills
    private var enabledProviders: [Account] {
        monitor.lineup
    }

    /// Room above the scrolled cards for an outlined theme's thick top
    /// outline (and hover lift), which the scroll view would otherwise clip.
    /// Taken from the gap under the pills, so the spacing doesn't change.
    private var scrollTopInset: CGFloat {
        theme.isOutlined ? 4 : 0
    }

    private var providerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Leaderboard leads the row, but the popover still opens on
                // the first provider: it shows only once it's picked.
                // Gone while the Leaderboard is turned off.
                // All leads, the Leaderboard follows, then a divider: the pages
                // about every provider, then a pill per provider.
                if overview.isOffered {
                    AllProvidersPill(isSelected: showsAll) { page = .all }
                        .help("All providers (⌘0)")
                }
                if leaderboard.membership.isOn {
                    LeaderboardPill(isSelected: showsLeaderboard) { page = .leaderboard }
                        .help("Leaderboard")
                }
                if overview.isOffered || leaderboard.membership.isOn {
                    PillDivider()
                }
                ForEach(Array(monitor.tabs.enumerated()), id: \.element.id) { index, tab in
                    ProviderPill(
                        providerId: tab.id,
                        providerName: settings.shown(tab.name),
                        isSelected: shownPage == .provider && tab.contains(selectedProviderId),
                        hasData: tab.accounts.contains { $0.snapshot != nil }
                    ) {
                        // Avoid withAnimation to prevent constraint update loops in MenuBarExtra
                        page = .provider
                        if !tab.contains(selectedProviderId), let first = tab.accounts.first {
                            selectedProviderId = first.id
                        }
                    }
                    .help(index < 9 ? "\(settings.shown(tab.name)) (⌘\(index + 1))" : settings.shown(tab.name))
                }
            }
            // A scroll view clips at its edges: leave room for an outlined
            // theme's thick outline and hard shadow.
            .padding(.vertical, theme.isOutlined ? 5 : 0)
            .padding(.leading, theme.isOutlined ? 2 : 0)
            .padding(.trailing, theme.isOutlined ? 5 : 0)
            .background(HorizontalScrollBooster())
            .overlay {
                GeometryReader { geo in
                    Color.clear.preference(key: PillsContentWidthKey.self, value: geo.size.width)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PillsViewportWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(PillsContentWidthKey.self) { contentWidth in
            updatePillsOverflow(contentWidth: contentWidth)
        }
        .onPreferenceChange(PillsViewportWidthKey.self) { viewportWidth in
            updatePillsOverflow(viewportWidth: viewportWidth)
        }
        .mask {
            HStack(spacing: 0) {
                Rectangle().fill(.white)
                if pillsOverflow {
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIn)
    }

    private func updatePillsOverflow(contentWidth: CGFloat? = nil, viewportWidth: CGFloat? = nil) {
        if let contentWidth { pillsContentWidth = contentWidth }
        if let viewportWidth { pillsViewportWidth = viewportWidth }
        let overflows = pillsViewportWidth > 0 && pillsContentWidth > pillsViewportWidth + 1
        if pillsOverflow != overflows {
            pillsOverflow = overflows
        }
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if let notice = leaderboard.offNotice {
            LeaderboardOffNoticeCard(notice: notice) {
                withAnimation(.easeInOut(duration: 0.2)) { leaderboard.turnOn() }
            }
        }
        if showsLeaderboard {
            LeaderboardPopoverView(leaderboard: leaderboard, monitor: monitor)
        } else if showsAll {
            OverviewPageView(overview: overview) { card in
                // A tap opens the provider on its first login.
                if let first = card.firstLoginId { selectedProviderId = first }
                page = .provider
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if let tab = monitor.selectedTab, tab.accounts.count > 1 {
            accountsContent(tab)
        } else if let provider = selectedLogin, let snapshot = monitor.usage(of: provider) {
            let report = RefreshReport.of(provider)
            VStack(spacing: 12) {
                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    AccountCardView(
                        providerId: selectedProviderId, displayName: displayName, snapshot: snapshot,
                        freshness: report.freshness ?? "Updated \(snapshot.ageDescription)"
                    )
                } else if let freshness = report.freshness {
                    freshnessLine(freshness)
                }
                if let failure = report.failure {
                    failureNotice(failure)
                }
                statsGrid(snapshot: snapshot)
                    .opacity(report.isLastSeen ? 0.55 : 1)
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if let account = selectedLogin, account.needsSetup {
            setupContent(account)
                .opacity(animateIn ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if selectedLogin?.isSyncing == true {
            loadingState
        } else {
            emptyState
        }
    }

    /// One product, every enabled login side by side: chips that hide one
    /// from this view, a section per login, and the login that makes the
    /// product's status what it is, named.
    private func accountsContent(_ tab: ProductTab) -> some View {
        VStack(spacing: 12) {
            accountChips(tab)
            if let state = newSessions.state(of: tab.provider) {
                InUseStrip(state: state)
            }
            ForEach(tab.accounts.filter { !hiddenAccountIds.contains($0.id) }, id: \.id) { account in
                providerSection(provider: account)
            }
            if let worst = tab.provider.accounts.worst {
                worstAccountCallout(worst)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
    }

    private func accountChips(_ tab: ProductTab) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("ACCOUNTS")
                    .popoverFont(9, weight: .semibold)
                    .foregroundStyle(theme.textTertiary)
                ForEach(tab.accounts, id: \.id) { account in
                    let hidden = hiddenAccountIds.contains(account.id)
                    HStack(spacing: 4) {
                        Button {
                            if hidden { hiddenAccountIds.remove(account.id) } else { hiddenAccountIds.insert(account.id) }
                        } label: {
                            HStack(spacing: 4) {
                                if tab.provider.inUse?.isInUse(account) == true { InUseBadge() }
                                Text(settings.shown(tab.provider.lineupName(of: account))).lineLimit(1)
                                Circle()
                                    .fill(account.lastError != nil ? theme.textTertiary
                                          : theme.statusColor(for: monitor.status(of: account) ?? .healthy))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(hidden ? "Show \(settings.shown(tab.provider.lineupName(of: account)))" : "Hide \(settings.shown(tab.provider.lineupName(of: account))) from this view")
                        // One click switches: the other logins end in "Use".
                        if tab.provider.inUse?.canBeInUse(account) == true, tab.provider.inUse?.isInUse(account) != true {
                            Button { newSessions.use(account) } label: {
                                Text("Use")
                                    .popoverFont(10, weight: .bold)
                                    .foregroundStyle(theme.accentPrimary)
                            }
                            .buttonStyle(.plain)
                            .help("Use \(settings.shown(tab.provider.lineupName(of: account))) for new terminal sessions")
                            .accessibilityLabel("Use \(settings.shown(tab.provider.lineupName(of: account))) for new terminal sessions")
                        }
                    }
                    .popoverFont(11, weight: .medium)
                    // The provider pills' shape and height. A leading IN USE badge sits
                    // concentric: the same gap on its left as above and below it.
                    .frame(height: InUseBadge.chipHeight(in: theme))
                    .padding(.leading, tab.provider.inUse?.isInUse(account) == true ? InUseBadge.gap(in: theme) : 10)
                    .padding(.trailing, 10)
                    .background(RoundedRectangle(cornerRadius: theme.pillCornerRadius).fill(hidden ? Color.clear : theme.glassBackground))
                    // Stroked across the edge, as the provider pills and the cards are:
                    // its anti-aliasing falls evenly on both sides, so the bottom edge
                    // is as heavy as the top. (strokeBorder lost the bottom's half pixel.)
                    .overlay(RoundedRectangle(cornerRadius: theme.pillCornerRadius).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
                    .foregroundStyle(hidden ? theme.textTertiary : theme.textPrimary)
                    .contextMenu {
                        if tab.provider.inUse?.canBeInUse(account) == true {
                            Button("Use for New Terminal Sessions") { newSessions.use(account) }.disabled(tab.provider.inUse?.isInUse(account) == true)
                        }
                    }
                }
            }
            // As the provider pills: a scroll view clips at its edges, so leave
            // room for an outlined theme's thick outline.
            .padding(.vertical, theme.isOutlined ? 5 : 1)
            .padding(.leading, theme.isOutlined ? 2 : 1)
            .padding(.trailing, theme.isOutlined ? 5 : 1)
        }
    }

    /// "Work is at 18% Session — causing Warning": the aggregate names its cause.
    private func worstAccountCallout(_ worst: Account) -> some View {
        let status = monitor.status(of: worst) ?? worst.status
        let lowest = monitor.usage(of: worst)?.lowestQuota
        let detail = lowest.map { " is at \(Int($0.percentRemaining))% \($0.quotaType.displayName)" } ?? ""
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.statusColor(for: status))
            Text("\(settings.shown(worst.displayName))\(detail) — causing \(status.badgeText.capitalized)")
                .popoverFont(11)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.statusColor(for: status).opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.statusColor(for: status).opacity(0.4), lineWidth: 1))
    }

    private func providerSection(provider: Account) -> some View {
        VStack(spacing: 8) {
            providerSectionHeader(provider: provider)

            if let snapshot = monitor.usage(of: provider) {
                let report = RefreshReport.of(provider)
                if let failure = report.failure {
                    failureNotice(failure)
                }
                statsGrid(snapshot: snapshot)
                    .opacity(report.isLastSeen ? 0.55 : 1)
            } else if provider.needsSetup {
                setupContent(provider)
            } else if provider.isSyncing {
                LoadingSpinnerView()
            } else {
                compactErrorState(provider: provider)
            }
        }
    }

    private func providerSectionHeader(provider: Account) -> some View {
        HStack(spacing: 8) {
            ProviderIconView(providerId: provider.id, size: 20, showGlow: false)

            Text(settings.shown(monitor.lineupName(of: provider)))
                .fixedSize(horizontal: false, vertical: true)
                .popoverFont(13, weight: .semibold)
                .foregroundStyle(theme.textPrimary)

            Spacer()

            // The same word the header uses: no "HEALTHY" without data (#259).
            let badge = ProviderBadgeState(of: [provider], quotaStatus: monitor.status(of: provider))
            Text(badge.badgeText(in: theme))
                .badge(badge.badgeColor(theme))
                .opacity(badge.showsBadge ? 1 : 0)
        }
        .padding(.horizontal, 4)
    }

    /// "Updated 2m ago · via RPC" when there is no account card to carry it.
    private func freshnessLine(_ text: String) -> some View {
        HStack {
            Text(text)
                .popoverFont(10, weight: .semibold)
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    /// A failed refresh over the last usage: the step that failed, then what to do.
    private func failureNotice(_ failure: RefreshReport.Failure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .popoverFont(12)
                .foregroundStyle(theme.statusWarning)

            VStack(alignment: .leading, spacing: 2) {
                if let headline = failure.headline {
                    Text(headline)
                        .popoverFont(11, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                }
                Text(failure.detail)
                    .help(failure.detail)
                    .popoverFont(11, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func compactErrorState(provider: Account) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .popoverFont(12)
                .foregroundStyle(theme.statusWarning)

            Text(provider.lastError?.localizedDescription ?? "Unavailable")
                .help(provider.lastError?.localizedDescription ?? "Unavailable")
                .popoverFont(11, weight: .medium)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }


    /// Collapsed state of quota-group sections, keyed by `QuotaGroup.id`.
    /// Ephemeral by design: reopening the popover starts fully expanded.
    @State private var collapsedQuotaGroups: Set<String> = []

    /// Sections for aggregating providers (e.g. Oh My Pi): one collapsible
    /// block per upstream account, so ten flat cards become scannable.
    @ViewBuilder
    private func quotaGroupSections(snapshot: UsageSnapshot) -> some View {
        let groups = snapshot.quotaGroups
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                let baseDelay = Double(groups.prefix(groupIndex).reduce(0) { $0 + $1.quotas.count }) * 0.08
                quotaGroupSection(group, baseDelay: baseDelay)
            }
        }
    }

    private func quotaGroupSection(_ group: QuotaGroup, baseDelay: Double) -> some View {
        // Note-only sections (accounts without usable quota data) have no
        // cards to collapse; the note renders inline in the header.
        let isNoteOnly = group.quotas.isEmpty
        let isCollapsed = !isNoteOnly && collapsedQuotaGroups.contains(group.id)
        let sharedReset = group.quotas.sharedResetDescription()
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    collapsedQuotaGroups = isCollapsed
                        ? collapsedQuotaGroups.subtracting([group.id])
                        : collapsedQuotaGroups.union([group.id])
                }
            } label: {
                HStack(spacing: 6) {
                    if !isNoteOnly {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .popoverFont(8, weight: .bold)
                            .foregroundStyle(theme.textTertiary)
                    }

                    sectionTitle((group.title ?? "Other").uppercased())

                    Spacer(minLength: 4)

                    if case .headerInline(let note) = group.notePlacement {
                        Text(note)
                            .popoverFont(9, weight: .medium)
                            .foregroundStyle(theme.textTertiary)
                    } else if isNoteOnly {
                        Text("No usage data")
                            .popoverFont(9, weight: .medium)
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        // Collapsed sections keep their headline number visible.
                        if isCollapsed, let lowest = group.lowestQuota {
                            Text("\(Int(lowest.percentRemaining))% left")
                                .popoverFont(9, weight: .semibold)
                                .foregroundStyle(theme.textTertiary)
                        }

                        Text(theme.statusWord(for: group.worstStatus))
                            .badge(theme.statusColor(for: group.worstStatus))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isNoteOnly)

            if !isNoteOnly && !isCollapsed {
                // A note attached to a quota-bearing section (the same
                // account also reported "No usage" somewhere) is shown as
                // its own row - never silently dropped.
                if case .row(let note) = group.notePlacement {
                    Text(note)
                        .popoverFont(9, weight: .medium)
                        .foregroundStyle(theme.textTertiary)
                }

                if let sharedReset {
                    sharedResetRow(sharedReset)
                }

                TwoColumnCardGrid(
                    items: Array(group.quotas.enumerated()),
                    id: \.element.quotaType
                ) { entry in
                    WrappedStatCard(
                        quota: entry.element,
                        delay: baseDelay + Double(entry.offset) * 0.08,
                        showsReset: sharedReset == nil
                    )
                }
            }
        }
    }

    private func sharedResetRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .popoverFont(8)

            Text(text)
                .popoverFont(10, weight: .medium)

            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.textTertiary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func statsGrid(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 10) {
            // Grouped sections cover aggregating providers even when every
            // account lacks quota data (note-only sections must still render).
            if snapshot.hasQuotaGroups {
                quotaGroupSections(snapshot: snapshot)
            }

            if !snapshot.hasQuotaGroups, !snapshot.quotas.isEmpty {
                let sharedReset = snapshot.quotas.sharedResetDescription()
                if let sharedReset {
                    sharedResetRow(sharedReset)
                }
            }

            if !snapshot.hasQuotaGroups, !snapshot.quotas.isEmpty {
                let sharedReset = snapshot.quotas.sharedResetDescription()
                TwoColumnCardGrid(
                    items: Array(snapshot.quotas.enumerated()),
                    id: \.element.quotaType
                ) { entry in
                    WrappedStatCard(
                        quota: entry.element,
                        delay: Double(entry.offset) * 0.08,
                        showsReset: sharedReset == nil
                    )
                }
            }

            // Show Extra usage cost card if available (Pro with Extra usage enabled)
            if let costUsage = snapshot.costUsage {
                // The Claude API budget judges Claude's own cost, never another provider's.
                let budget = settings.claudeApiBudgetEnabled && snapshot.providerId.hasPrefix("claude") ? settings.claudeApiBudget : nil
                CostStatCard(costUsage: costUsage, budget: budget, delay: Double(snapshot.quotas.count) * 0.08)
            }

            // Under per-account sections, today needs its own title, or it
            // reads as part of the last account's section.
            todaySection(account: monitor.login(id: snapshot.providerId),
                         fallback: snapshot.dailyUsageReport, after: snapshot.quotas.count,
                         titled: snapshot.hasQuotaGroups)

            // Show extension metrics cards (from extension probes)
            if let extensionMetrics = snapshot.extensionMetrics?.filter({ $0.group == nil }),
               !extensionMetrics.isEmpty {
                let metricBaseDelay = Double(snapshot.quotas.count + 2) * 0.08
                TwoColumnCardGrid(
                    items: Array(extensionMetrics.enumerated()),
                    id: \.element.label
                ) { entry in
                    ExtensionMetricCardView(metric: entry.element, delay: metricBaseDelay + Double(entry.offset) * 0.08)
                }
            }

            // Show custom web card if URL is configured for this provider
            if let urlString = settings.provider.customCardURL(forProvider: snapshot.providerId),
               let url = URL(string: urlString) {
                let cardDelay = Double(snapshot.quotas.count + 2) * 0.08
                CustomWebCardView(url: url, delay: cardDelay)
            }
        }
        .padding(.top, 4)
    }

    /// *TODAY* — the login's own daily usage cards, a card per other app on
    /// this Mac (Claude Desktop), and the thirty-day chart. Shown under the
    /// limits, and under the setup card when there are none yet (#198).
    /// `titled` heads it *TODAY'S USAGE*, in the quota sections' style.
    @ViewBuilder
    private func todaySection(account: Account?, fallback: DailyUsageReport?, after cards: Int,
                              titled: Bool = false) -> some View {
        let history = account?.usageHistory
        let report = history?.report ?? fallback
        let apps = history?.usedOtherApps ?? []
        let lastThirtyDays = history?.lastThirtyDays
        if titled, settings.showDailyUsageCards, report != nil || !apps.isEmpty || lastThirtyDays != nil {
            HStack {
                sectionTitle("TODAY'S USAGE")
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        }

        if settings.showDailyUsageCards, let report {
            let baseDelay = Double(cards + 1) * 0.08
            // Logs that can't be priced show no cost rather than a made-up $0.
            let knowsCost = history?.knowsCost ?? true
            HStack(spacing: 10) {
                if knowsCost {
                    DailyUsageCardView(metric: .cost, report: report, delay: baseDelay)
                        .frame(maxWidth: .infinity)
                }
                DailyUsageCardView(metric: .tokens, report: report, delay: baseDelay + 0.08)
                    .frame(maxWidth: .infinity)
            }
            if report.hasWorkingTime {
                DailyUsageCardView(metric: .workingTime, report: report, delay: baseDelay + 0.16)
            }
        }

        // Other apps on this Mac that use the same plan (Claude Desktop):
        // a tokens card each, shown even when the login's own logs are empty.
        if settings.showDailyUsageCards, !apps.isEmpty {
            let appDelay = Double(cards + 3) * 0.08
            TwoColumnCardGrid(items: apps, id: \.label) { app in
                if let report = app.report {
                    DailyUsageCardView(metric: .tokens, report: report, delay: appDelay, title: app.label)
                }
            }
        }

        // The same login's last thirty days, as a chart.
        if settings.showDailyUsageCards, let lastThirtyDays {
            UsageHistoryChartView(days: lastThirtyDays)
        }
    }

    /// A section's title above its cards: an account's quotas, or today.
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .popoverFont(9, weight: .semibold)
            .foregroundStyle(theme.textSecondary)
            .tracking(0.5)
    }

    /// *NOT SET UP* — nothing to read the limits with yet. Says what it
    /// takes, in the definition's words, and keeps what can be read: today.
    private func setupContent(_ account: Account) -> some View {
        VStack(spacing: 12) {
            setupCard(account)
            todaySection(account: account, fallback: nil, after: 0)
        }
    }

    private func setupCard(_ account: Account) -> some View {
        let setup = monitor.setupNotice(of: account)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.0percent")
                    .popoverFont(12, weight: .semibold)
                    .foregroundStyle(theme.textSecondary)
                Text(setup.title)
                    .popoverFont(12, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            Text(setup.text)
                .popoverFont(11, weight: .medium)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = setup.url {
                Button(setup.button) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
                    .popoverFont(28)
                    .foregroundStyle(theme.statusWarning)
            }

            // A provider that is data names the step that failed first.
            let failure = selectedLogin.flatMap { RefreshReport.of($0).failure }
            Text(failure?.headline ?? "\(selectedLogin.map(monitor.lineupName(of:)) ?? selectedProviderId) Unavailable")
                .popoverFont(14, weight: .bold)
                .foregroundStyle(theme.textPrimary)

            // Show actual error message if available, otherwise generic message
            Text(failure?.headline != nil
                 ? "\(selectedLogin.map(monitor.lineupName(of:)) ?? selectedProviderId) Unavailable · \(failure?.detail ?? "")"
                 : selectedLogin?.lastError?.localizedDescription ?? "Install CLI or check configuration")
                .popoverFont(11, weight: .semibold)
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
                if let url = selectedLogin.flatMap(monitor.dashboardURL(of:)) {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("d")
            .help("Open dashboard (⌘D)")

            // Refresh Button — always here, a ? block in the header or not.
            WrappedActionButton(
                icon: isCurrentlyRefreshing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isCurrentlyRefreshing ? "Syncing" : "Refresh",
                gradient: theme.accentGradient,
                isLoading: isCurrentlyRefreshing,
                action: refreshNow
            )
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")

            Spacer()

            // Share Button (Claude only) - icon only
            if let guestPasses, guestPasses.isOffered(for: selectedLogin?.snapshot) {
                let isFetchingPasses = guestPasses.isFetching
                Button {
                    Task { await fetchAndShowPasses() }
                } label: {
                    ZStack {
                        theme.controlShape
                            .fill(theme.shareGradient)
                            .themeShadow(theme, scale: 0.6)
                            .overlay(theme.controlShape.stroke(theme.isOutlined ? theme.glassBorder : .clear, lineWidth: theme.cardBorderWidth))
                            .frame(width: 32, height: 32)

                        // On a printed theme's light candy fill, the icon is ink.
                        if isFetchingPasses {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(theme.isOutlined ? theme.textPrimary : .white)
                        } else {
                            Image(systemName: "gift.fill")
                                .popoverFont(12, weight: .bold)
                                .foregroundStyle(theme.isOutlined ? theme.textPrimary : .white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Share Claude Code (⌘S)")
                .keyboardShortcut("s")
            }

            // Settings Button with update indicator
            Button {
                // Settings live in a standalone window. The app is an
                // LSUIElement, so activate it to bring the window forward.
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                ZStack {
                    theme.controlShape
                        .fill(theme.glassBackground)
                        .themeShadow(theme, scale: 0.6)
                        .overlay(theme.controlShape.stroke(theme.isOutlined ? theme.glassBorder : .clear, lineWidth: theme.cardBorderWidth))
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .popoverFont(12, weight: .bold)
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
                    theme.controlShape
                        .fill(theme.glassBackground)
                        .themeShadow(theme, scale: 0.6)
                        .overlay(theme.controlShape.stroke(theme.isOutlined ? theme.glassBorder : .clear, lineWidth: theme.cardBorderWidth))
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .popoverFont(12, weight: .bold)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeBar (⌘Q)")
            .keyboardShortcut("q")
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateIn)
    }

    // MARK: - Actions

    /// Refresh all enabled providers concurrently
    /// - Parameter kind: `.interactive` for explicit clicks (Refresh button),
    ///   `.passive` for the popover-open refresh (issue #216).
    private func refreshAllEnabled(kind: RefreshKind = .interactive) async {
        await withTaskGroup(of: Void.self) { group in
            // The `isSyncing` guard reads main-actor provider state, so evaluate
            // it here on the main actor (this closure inherits the caller's
            // isolation). Each child task then awaits `refresh(_:)`, whose heavy
            // probe work still suspends off-main, keeping the refreshes concurrent.
            for provider in monitor.lineup where !provider.isSyncing {
                guard let product = monitor.product(of: provider) else { continue }
                group.addTask {
                    do {
                        try await product.refresh(provider, kind)
                    } catch {
                        // Provider stores error in lastError
                    }
                }
            }
        }
        for provider in monitor.lineup {
            await provider.usageHistory?.read()
        }
    }

    /// Refresh a specific provider by ID
    /// - Parameter kind: `.interactive` for explicit clicks (Refresh button,
    ///   provider switch), `.passive` for the popover-open refresh (issue #216).
    private func refresh(providerId: String, kind: RefreshKind = .interactive) async {
        // A tab of logins refreshes every login it shows.
        let members = monitor.tabs.first { $0.contains(providerId) }?.accounts
            ?? monitor.login(id: providerId).map { [$0] } ?? []
        // Provider stores error in lastError; isSyncing prevents duplicates.
        let refreshes: [Task<Void, Never>] = members.filter { !$0.isSyncing }.compactMap { login in
            guard let product = monitor.product(of: login) else { return nil }
            return Task { _ = try? await product.refresh(login, kind) }
        }
        // Today's usage is read with the popover open, never in the background.
        let history = members.compactMap(\.usageHistory).map { history in Task { await history.read() } }
        for refresh in refreshes { await refresh.value }
        for read in history { await read.value }
    }

    /// The selected provider's guest passes, when it has any to offer.
    private var guestPasses: GuestPasses? {
        selectedLogin?.guestPasses
    }

    /// Fetch guest passes and show the share view
    private func fetchAndShowPasses() async {
        guard let guestPasses else {
            return
        }

        // Prevent duplicate fetches
        guard !guestPasses.isFetching else { return }

        do {
            _ = try await guestPasses.fetch()
            withAnimation(.easeInOut(duration: 0.2)) {
                showSharePass = true
            }
        } catch {
            // Provider stores the error in passError, which the popover surfaces
            // as SharePassErrorOverlay — a failed click is never silent.
        }
    }
}

// MARK: - Provider Pill

struct ProviderPill: View {
    let providerId: String
    let providerName: String
    let isSelected: Bool
    let hasData: Bool
    /// A symbol of its own, for a tab that isn't a provider.
    var symbol: String? = nil
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol ?? providerIcon)
                    .popoverFont(10, weight: .semibold)

                Text(providerName)
                    .help(providerName)
                    .popoverFont(11, weight: .medium)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? theme.textOnAccent : theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        if theme.isOutlined {
                            // Printed: an inked chip with a hard shadow, no glow.
                            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                                .fill(theme.accentGradient)
                                .themeShadow(theme, scale: 0.5)
                        } else {
                            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                                .fill(theme.accentGradient)
                                .shadow(color: theme.accentPrimary.opacity(0.3), radius: 6, y: 2)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(isHovering ? theme.hoverOverlay : theme.glassBackground)
                    }

                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(isSelected && !theme.isOutlined ? theme.accentPrimary.opacity(0.5) : theme.glassBorder,
                                lineWidth: theme.cardBorderWidth)
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

/// The pill that opens the All page, styled as a provider's.
struct AllProvidersPill: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ProviderPill(providerId: "all", providerName: "All", isSelected: isSelected, hasData: true,
                     symbol: "square.grid.2x2.fill", action: action)
    }
}

/// The line between the pages about every provider and the providers' pills.
struct PillDivider: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(theme.isOutlined ? theme.glassBorder : theme.textTertiary.opacity(0.5))
            .frame(width: theme.isOutlined ? 2.5 : 1.5, height: 16)
            .padding(.horizontal, 2)
    }
}

/// The pill that opens the Leaderboard tab, styled as a provider's.
struct LeaderboardPill: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        ProviderPill(providerId: "leaderboard", providerName: "Leaderboard", isSelected: isSelected, hasData: true,
                     symbol: "trophy.fill", action: action)
    }
}

// MARK: - Provider Pill Overflow

private struct PillsContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PillsViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Two-Column Card Grid

/// Non-lazy two-column grid for popover cards.
///
/// The popover shows at most a few dozen lightweight cards, so laziness buys
/// nothing — and `LazyVGrid` actively hurts: lazy containers report an
/// estimated height and correct it as cells materialize, and inside the
/// popover's vertical `ScrollView` each correction rewrites the scroll offset
/// mid-gesture. Scrolling upward trembled, snapped back, and only got through
/// with an exaggerated flick. An eager grid hands the scroll view exact
/// content heights up front, so dragging stays smooth in both directions.
///
/// Layout matches the `LazyVGrid` it replaces: two equal flexible columns,
/// `spacing` between rows and columns, cells center-aligned per row, and a
/// lone card in the last row keeps column width instead of stretching.
struct TwoColumnCardGrid<Item, ID: Hashable, Cell: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    var spacing: CGFloat = 10
    @ViewBuilder let cell: (Item) -> Cell

    init(
        items: [Item],
        id: KeyPath<Item, ID>,
        spacing: CGFloat = 10,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) {
        self.items = items
        self.id = id
        self.spacing = spacing
        self.cell = cell
    }

    /// A row's identity: its position plus the ids of the cards it holds.
    ///
    /// Keying a row on its leading card's id alone (the original form) is not
    /// unique: providers can report two cards of the same `QuotaType` — one
    /// `.session` per account, say — and two rows then claim the same `ForEach`
    /// id. Duplicate ids leave SwiftUI free to recycle one row's backing layer
    /// for another's content, which is one way cards end up drawing garbled
    /// (see #272). The position keeps ids unique whatever the cards contain,
    /// and the card ids keep a row's identity tied to what it actually shows.
    private struct RowID: Hashable {
        let index: Int
        let leading: ID
        let trailing: ID?
    }

    private var rows: [(id: RowID, leading: Item, trailing: Item?)] {
        stride(from: 0, to: items.count, by: 2).map { start in
            let trailing = start + 1 < items.count ? items[start + 1] : nil
            return (
                id: RowID(
                    index: start,
                    leading: items[start][keyPath: id],
                    trailing: trailing?[keyPath: id]
                ),
                leading: items[start],
                trailing: trailing
            )
        }
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.id) { row in
                HStack(spacing: spacing) {
                    cell(row.leading)
                        .frame(maxWidth: .infinity)
                    if let trailing = row.trailing {
                        cell(trailing)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Hold the empty slot so a lone final card keeps
                        // column width instead of stretching across the row.
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 0)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

// MARK: - Wrapped Stat Card

struct WrappedStatCard: View {
    let quota: UsageQuota
    let delay: Double
    var showsReset: Bool = true

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
        theme.statusColor(for: quota.status(under: settings.statusPolicy))
    }

    private var isCappedSpend: Bool {
        quota.dollarUsed != nil && quota.dollarCap != nil
    }

    private var valueCaption: String {
        if isCappedSpend { return "Spent" }
        if quota.isDollarBased { return "Remaining" }
        return QuotaCardText.caption(mode: effectiveDisplayMode, isOutlined: false)
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
                        .popoverFont(9, weight: .bold)
                        .foregroundStyle(statusColor)

                    Text((quota.compactTitle ?? quota.quotaType.displayName).uppercased())
                        .popoverFont(8, weight: .medium)
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.3)
                }

                Spacer(minLength: 4)

                // Status badge - pace mode shows pace badge, others show status
                if effectiveDisplayMode == .pace {
                    Text(quota.pace.displayName.uppercased())
                        .badge(paceColor)
                } else {
                    let status = quota.status(under: settings.statusPolicy)
                    Text(theme.statusWord(for: status))
                        .badge(statusColor)
                        .blinking(theme.blinks(status))
                }
            }

            // Large value display with label (end-aligned).
            //
            // The headline number deliberately carries no
            // `.contentTransition(.numericText())`: that modifier hands the
            // digits to a separate morphing text layer, and those layers are
            // what users see come back mirrored after a refresh (#272) — the
            // flipped fields are the ones whose value just changed. A number
            // that reads correctly is worth more than a rolling animation.
            HStack(alignment: .firstTextBaseline) {
                if theme.isOutlined {
                    // Printed: every headline outlined — "62%" and "$24.19"
                    // alike (#499) — its short caption right beside it.
                    let headline = QuotaCardText.headline(for: quota, mode: effectiveDisplayMode)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        OutlinedNumber(
                            text: headline.number,
                            size: 28,
                            color: isPercent && effectiveDisplayMode == .pace ? paceColor : nil
                        )
                        .layoutPriority(1)
                        Text(headline.caption)
                            .font(theme.font(size: 9, weight: .heavy))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                } else if let dollarUsed = quota.formattedDollarUsed,
                   let dollarCap = quota.formattedDollarCap {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(dollarUsed)
                            .font(theme.displayFont(size: 20, weight: .heavy))
                            .foregroundStyle(theme.textPrimary)

                        Text("of \(dollarCap)")
                            .popoverFont(9, weight: .semibold)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                } else if let dollarText = quota.formattedDollarRemaining {
                    Text(dollarText)
                        .popoverDisplayFont(18)
                        .foregroundStyle(theme.textPrimary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(quota.displayPercent(mode: effectiveDisplayMode)))")
                            .font(theme.displayFont(size: 26))
                            .foregroundStyle(effectiveDisplayMode == .pace ? paceColor : theme.textPrimary)

                        Text("%")
                            .font(theme.font(size: 13, weight: .medium))
                            .foregroundStyle(effectiveDisplayMode == .pace ? paceColor.opacity(0.7) : theme.textTertiary)
                    }
                }

                Spacer(minLength: 4)

                if !theme.isOutlined {
                    Text(valueCaption)
                        .font(theme.font(size: isCappedSpend ? 10 : 12, weight: .medium))
                        .fixedSize()
                        .foregroundStyle(effectiveDisplayMode == .pace ? paceColor.opacity(0.8) : theme.textTertiary)
                }
            }

            // Progress bar with the pace tick under it
            VStack(spacing: 1) {
                QuotaProgressBar(
                    percent: quota.displayProgressPercent(mode: effectiveDisplayMode),
                    fill: theme.progressGradient(for: quota.status(under: settings.statusPolicy)),
                    animate: animateProgress,
                    delay: delay
                )

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
                        .fill(quota.paceLevel?.displayColor ?? theme.textTertiary)
                        .opacity(animateProgress ? 1 : 0)
                        .animation(.easeIn(duration: 0.3).delay(delay + 0.5), value: animateProgress)
                    }
                    .frame(height: 5)
                }
            }
            .help(quota.paceTickHelp(mode: effectiveDisplayMode) ?? "")

            // Reset info (hidden when the grid hoisted a shared countdown)
            if showsReset, let resetText = quota.resetTimestampDescription ?? quota.resetText ?? quota.resetDescription {
                if theme.isOutlined {
                    // Always one row, the time always whole. As the card
                    // narrows, "Resets in" gives way to a clock, then the
                    // badge's words to the pace's icon.
                    let line = QuotaCardText.ResetLine(resetText)
                    let timeOnly = line.time.map { QuotaCardText.ResetLine(time: $0) } ?? line
                    ViewThatFits(in: .horizontal) {
                        resetFooter(compactBadge: false) { resetLine(line) }
                        resetFooter(compactBadge: false) { clockedResetLine(timeOnly) }
                        resetFooter(compactBadge: true) { clockedResetLine(timeOnly) }
                    }
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill")
                            .popoverFont(7)

                        Text(resetText)
                            .popoverFont(8, weight: .medium)
                    }
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                }
            } else if showsPaceBadge {
                HStack { Spacer(); PaceBadge(pace: quota.pace) }
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient).themeShadow(theme)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
            }
        )
        .themeRivets()
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            animateProgress = true
        }
    }

    /// A plain percentage — not a dollar amount, which keeps its own layout.
    private var isPercent: Bool {
        !(quota.formattedDollarUsed != nil && quota.formattedDollarCap != nil)
            && quota.formattedDollarRemaining == nil
    }

    /// An outlined theme also names the pace in a footer badge — when the
    /// pace is known and isn't already the headline.
    private var showsPaceBadge: Bool {
        theme.isOutlined && quota.pace != .unknown && effectiveDisplayMode != .pace
    }

    /// "Resets in **2h 4m**": the lead muted, the time in ink.
    private func resetLine(_ line: QuotaCardText.ResetLine) -> Text {
        let time = line.time.map {
            Text($0)
                .font(theme.font(size: 8.5, weight: .heavy))
                .foregroundColor(theme.textPrimary)
        }
        guard !line.lead.isEmpty else { return time ?? Text("") }
        let lead = Text(line.lead)
            .font(theme.font(size: 8.5, weight: .semibold))
            .foregroundColor(theme.textTertiary)
        guard let time else { return lead }
        return lead + Text(" ") + time
    }

    /// A clock, then the reset time.
    private func clockedResetLine(_ line: QuotaCardText.ResetLine) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .popoverFont(7)
                .foregroundStyle(theme.textTertiary)
            resetLine(line)
        }
    }

    /// The reset time and, on the right, the pace badge, on one row.
    private func resetFooter(compactBadge: Bool, @ViewBuilder reset: () -> some View) -> some View {
        HStack(spacing: 4) {
            reset().fixedSize()
            Spacer(minLength: 2)
            if showsPaceBadge { PaceBadge(pace: quota.pace, compact: compactBadge) }
        }
    }

    private var iconName: String {
        let title = (quota.compactTitle ?? quota.quotaType.displayName).lowercased()
        if title.contains("build") { return "hammer.fill" }
        if title.contains("chat") { return "bubble.left.fill" }
        if title.contains("imagine") { return "sparkles" }

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
                    .stroke(theme.isOutlined ? theme.progressTrack : theme.textTertiary, lineWidth: theme.isOutlined ? 4 : 3)
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
                .font(theme.font(size: 13, weight: .medium))
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
                        .popoverFont(12, weight: .semibold)
                }

                Text(label)
                    .font(theme.font(size: 12, weight: theme.isOutlined ? .bold : .medium))
                    .fixedSize()
            }
            .foregroundStyle(isHovering && !theme.isOutlined ? .white : theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if theme.isOutlined {
                        // Printed: a paper chip on a hard shadow, mint under the
                        // pointer, sky while it works — never greyed out.
                        theme.controlShape
                            .fill(isLoading ? theme.accentSecondary : (isHovering ? theme.statusHealthy : theme.glassBackground))
                            .themeShadow(theme, scale: isHovering ? 1 : 0.75)
                    } else {
                        theme.controlShape
                            .fill(isHovering ? AnyShapeStyle(gradient) : AnyShapeStyle(theme.glassBackground))
                    }

                    theme.controlShape
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                }
            )
            .offset(x: theme.isOutlined && isHovering ? -1 : 0, y: theme.isOutlined && isHovering ? -1 : 0)
            .shadow(color: isHovering && !theme.isOutlined ? theme.accentPrimary.opacity(0.3) : .clear, radius: 8, y: 2)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // A disabled button is dimmed; a printed theme shows its sky "working"
        // chip at full strength instead, and simply ignores clicks meanwhile.
        .disabled(isLoading && !theme.isOutlined)
        .allowsHitTesting(!isLoading)
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
                .popoverFont(7, weight: .black)
                .foregroundStyle(.white)
        }
    }
}


