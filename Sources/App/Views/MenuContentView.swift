import SwiftUI
import Domain

/// The main menu content view with refined utilitarian design.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let appState: AppState

    @State private var selectedProvider: AIProvider = .claude
    @State private var isHoveringRefresh = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with branding
            headerView

            // Provider Segmented Switcher
            providerSwitcher
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            // Metrics Content
            metricsContent
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .geometryGroup()

            Divider()
                .padding(.horizontal, 16)

            // Action buttons
            actionButtons
                .padding(.vertical, 8)
        }
        .frame(width: 360)
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
        )
        .task {
            await refresh()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            // Logo with gradient
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("ClaudeBar")
                    .font(.system(size: 14, weight: .semibold))

                Text("AI Usage Monitor")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status Pill
            statusPill
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            // Animated status dot
            Circle()
                .fill(appState.overallStatus.displayColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(appState.overallStatus.displayColor.opacity(0.4), lineWidth: 2)
                        .scaleEffect(appState.isRefreshing ? 1.8 : 1.0)
                        .opacity(appState.isRefreshing ? 0 : 0.6)
                        .animation(
                            appState.isRefreshing
                                ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                                : .default,
                            value: appState.isRefreshing
                        )
                )

            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(appState.overallStatus.displayColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(appState.overallStatus.displayColor.opacity(0.12))
        )
    }

    private var statusText: String {
        if appState.isRefreshing { return "Syncing..." }
        switch appState.overallStatus {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .depleted: return "Depleted"
        }
    }

    // MARK: - Provider Switcher (Segmented)

    private var providerSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(AIProvider.allCases, id: \.self) { provider in
                ProviderTab(
                    provider: provider,
                    isSelected: provider == selectedProvider,
                    hasData: appState.snapshots[provider] != nil
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedProvider = provider
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.06))
        )
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if let snapshot = appState.snapshots[selectedProvider] {
            VStack(spacing: 10) {
                // Account info bar
                if let email = snapshot.accountEmail {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("Updated \(snapshot.ageDescription)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }

                // Metric Cards Grid
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(snapshot.quotas, id: \.quotaType) { quota in
                        MetricCard(quota: quota)
                    }
                }
            }
        } else if appState.isRefreshing {
            loadingState
        } else {
            emptyState
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)

            Text("Fetching usage data...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(height: 100)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)

            Text("\(selectedProvider.name) not available")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Install CLI or check configuration")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 100)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Dashboard Button
            ActionButton(
                icon: "safari",
                label: "Dashboard",
                shortcut: "D"
            ) {
                if let url = selectedProvider.dashboardURL {
                    NSWorkspace.shared.open(url)
                }
            }

            // Refresh Button
            ActionButton(
                icon: "arrow.clockwise",
                label: "Refresh",
                shortcut: "R",
                isLoading: appState.isRefreshing
            ) {
                Task { await refresh() }
            }

            Spacer()

            // Quit Button (compact)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeBar (⌘Q)")
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func refresh() async {
        // Guard against concurrent refreshes
        guard !appState.isRefreshing else { return }

        appState.isRefreshing = true
        defer { appState.isRefreshing = false }

        do {
            appState.snapshots = try await monitor.refreshAll()
            appState.lastError = nil

            if appState.snapshots[selectedProvider] == nil,
               let first = appState.snapshots.keys.first {
                selectedProvider = first
            }
        } catch {
            appState.lastError = error.localizedDescription
        }
    }
}

// MARK: - Provider Tab

struct ProviderTab: View {
    let provider: AIProvider
    let isSelected: Bool
    let hasData: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Provider Icon
                Image(systemName: providerIcon)
                    .font(.system(size: 11, weight: .medium))

                Text(provider.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isHovering && !isSelected ? Color.primary.opacity(0.04) : Color.clear)
                    )
            )
            .overlay(
                // Data indicator dot
                Group {
                    if hasData && !isSelected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .offset(x: 20, y: -8)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var providerIcon: String {
        switch provider {
        case .claude: return "brain"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .gemini: return "sparkles"
        }
    }
}

// MARK: - Metric Card (Refined)

struct MetricCard: View {
    let quota: UsageQuota

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))

                Text(quota.quotaType.displayName)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)

            // Value with color
            Text("\(Int(quota.percentRemaining))%")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(quota.status.displayColor)

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))

                    // Fill with gradient
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [quota.status.displayColor, quota.status.displayColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * quota.percentRemaining / 100)
                }
            }
            .frame(height: 4)

            // Reset info
            if let resetText = quota.resetText ?? quota.resetDescription {
                Text(resetText)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { isHovering = $0 }
    }

    private var iconName: String {
        switch quota.quotaType {
        case .session: return "clock.fill"
        case .weekly: return "calendar"
        case .modelSpecific: return "cpu.fill"
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let shortcut: String
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }

                Text(label)
                    .font(.system(size: 12, weight: .medium))

                Text("⌘\(shortcut)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(isHovering ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character(shortcut.lowercased())), modifiers: .command)
    }
}

// MARK: - Visual Effect Blur (macOS)

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
