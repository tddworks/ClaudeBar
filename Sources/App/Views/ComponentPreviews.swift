import SwiftUI
import Domain

// MARK: - Component Previews
// Preview all UI components in one place

// MARK: - Provider Icons Preview

struct ProviderIcons_Previews: PreviewProvider {
    static var previews: some View {
    let theme = DarkTheme()
    return HStack(spacing: 40) {
        VStack(spacing: 8) {
            ProviderIconView(providerId: "claude", size: 32)
            Text("Claude")
                .font(.caption)
                .foregroundColor(.white)
        }
        VStack(spacing: 8) {
            ProviderIconView(providerId: "codex", size: 32)
            Text("Codex")
                .font(.caption)
                .foregroundColor(.white)
        }
        VStack(spacing: 8) {
            ProviderIconView(providerId: "gemini", size: 32)
            Text("Gemini")
                .font(.caption)
                .foregroundColor(.white)
        }
        VStack(spacing: 8) {
            ProviderIconView(providerId: "zai", size: 32)
            Text("Z.ai")
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
    }
}

// MARK: - Provider Pills Preview

struct ProviderPills_Previews: PreviewProvider {
    static var previews: some View {
    let theme = DarkTheme()
    return VStack(spacing: 20) {
        // Selected states
        HStack(spacing: 8) {
            ProviderPill(providerId: "claude", providerName: "Claude", isSelected: true, hasData: true) {}
            ProviderPill(providerId: "codex", providerName: "Codex", isSelected: false, hasData: true) {}
            ProviderPill(providerId: "gemini", providerName: "Gemini", isSelected: false, hasData: false) {}
            ProviderPill(providerId: "zai", providerName: "Z.ai", isSelected: false, hasData: true) {}
        }

        // Different selection (Z.ai selected)
        HStack(spacing: 8) {
            ProviderPill(providerId: "claude", providerName: "Claude", isSelected: false, hasData: true) {}
            ProviderPill(providerId: "codex", providerName: "Codex", isSelected: false, hasData: true) {}
            ProviderPill(providerId: "gemini", providerName: "Gemini", isSelected: false, hasData: true) {}
            ProviderPill(providerId: "zai", providerName: "Z.ai", isSelected: true, hasData: true) {}
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
    }
}

// MARK: - Stat Cards Preview

struct StatCardsHealthy_Previews: PreviewProvider {
    static var previews: some View {
    let healthyQuota = UsageQuota(
        percentRemaining: 85,
        quotaType: .session,
        providerId: "claude",
        resetText: "Resets 11am"
    )

    WrappedStatCard(quota: healthyQuota, delay: 0)
        .frame(width: 160)
        .padding(20)
        .background(DarkTheme().backgroundGradient)
    }
}

struct StatCardsWarning_Previews: PreviewProvider {
    static var previews: some View {
    let warningQuota = UsageQuota(
        percentRemaining: 35,
        quotaType: .weekly,
        providerId: "claude",
        resetText: "Resets Dec 25"
    )

    WrappedStatCard(quota: warningQuota, delay: 0)
        .frame(width: 160)
        .padding(20)
        .background(DarkTheme().backgroundGradient)
    }
}

struct StatCardsCritical_Previews: PreviewProvider {
    static var previews: some View {
    let criticalQuota = UsageQuota(
        percentRemaining: 12,
        quotaType: .modelSpecific("Opus"),
        providerId: "claude",
        resetText: "Resets in 2h"
    )

    WrappedStatCard(quota: criticalQuota, delay: 0)
        .frame(width: 160)
        .padding(20)
        .background(DarkTheme().backgroundGradient)
    }
}

struct StatCardsGrid_Previews: PreviewProvider {
    static var previews: some View {
    let quotas = [
        UsageQuota(percentRemaining: 94, quotaType: .session, providerId: "claude", resetText: "Resets 11am"),
        UsageQuota(percentRemaining: 33, quotaType: .weekly, providerId: "claude", resetText: "Resets Dec 25"),
        UsageQuota(percentRemaining: 99, quotaType: .modelSpecific("Opus"), providerId: "claude", resetText: "Resets Dec 25"),
        UsageQuota(percentRemaining: 5, quotaType: .modelSpecific("Sonnet"), providerId: "claude", resetText: "Resets in 1h"),
    ]

    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(Array(quotas.enumerated()), id: \.offset) { index, quota in
            WrappedStatCard(quota: quota, delay: Double(index) * 0.1)
        }
    }
    .padding(20)
    .frame(width: 360)
    .background(DarkTheme().backgroundGradient)
    }
}

struct StatCardsZai_Previews: PreviewProvider {
    static var previews: some View {
    // Z.ai quotas showing session and time limit (MCP) usage
    let quotas = [
        UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "zai"),
        UsageQuota(percentRemaining: 70, quotaType: .timeLimit("MCP"), providerId: "zai"),
    ]

    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach(Array(quotas.enumerated()), id: \.offset) { index, quota in
            WrappedStatCard(quota: quota, delay: Double(index) * 0.1)
        }
    }
    .padding(20)
    .frame(width: 360)
    .background(DarkTheme().backgroundGradient)
    }
}

// MARK: - Status Badges Preview

struct StatusBadges_Previews: PreviewProvider {
    static var previews: some View {
    let theme = DarkTheme()
    return VStack(spacing: 16) {
        HStack(spacing: 12) {
            Text("HEALTHY")
            Text("WARNING")
            Text("LOW")
            Text("EMPTY")
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
    }
}

// MARK: - Action Buttons Preview

struct ActionButtons_Previews: PreviewProvider {
    static var previews: some View {
    let theme = DarkTheme()
    return HStack(spacing: 12) {
        WrappedActionButton(
            icon: "safari.fill",
            label: "Dashboard",
            gradient: ProviderVisualIdentityLookup.gradient(for: "claude", scheme: .dark)
        ) {}

        WrappedActionButton(
            icon: "arrow.clockwise",
            label: "Refresh",
            gradient: theme.accentGradient
        ) {}

        WrappedActionButton(
            icon: "arrow.clockwise",
            label: "Syncing",
            gradient: theme.accentGradient,
            isLoading: true
        ) {}
    }
    .padding(40)
    .background(theme.backgroundGradient)
    }
}

// MARK: - Loading Spinner Preview

struct LoadingSpinner_Previews: PreviewProvider {
    static var previews: some View {
    LoadingSpinnerView()
        .frame(width: 300)
        .background(DarkTheme().backgroundGradient)
    }
}

// MARK: - Glass Card Preview

struct GlassCards_Previews: PreviewProvider {
    static var previews: some View {
    VStack(spacing: 16) {
        Text("Glass Card Style")
            .font(.headline)
            .foregroundColor(.white)
            .glassCard()

        HStack {
            Image(systemName: "person.circle.fill")
            Text("user@example.com")
            Spacer()
            Text("Just now")
                .foregroundColor(.secondary)
        }
        .font(.caption)
        .foregroundColor(.white)
        .glassCard(cornerRadius: 12, padding: 10)
    }
    .padding(40)
    .frame(width: 300)
    .background(DarkTheme().backgroundGradient)
    }
}

// MARK: - Theme Colors Preview

struct ThemeColors_Previews: PreviewProvider {
    static var previews: some View {
    let theme = DarkTheme()
    return VStack(spacing: 20) {
        Text("Provider Colors")
            .font(.headline)
            .foregroundColor(.white)

        HStack(spacing: 20) {
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "claude", scheme: .dark)).frame(width: 40, height: 40)
                Text("Claude").font(.caption).foregroundColor(.white)
            }
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "codex", scheme: .dark)).frame(width: 40, height: 40)
                Text("Codex").font(.caption).foregroundColor(.white)
            }
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "gemini", scheme: .dark)).frame(width: 40, height: 40)
                Text("Gemini").font(.caption).foregroundColor(.white)
            }
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "zai", scheme: .dark)).frame(width: 40, height: 40)
                Text("Z.ai").font(.caption).foregroundColor(.white)
            }
        }

        Text("Status Colors")
            .font(.headline)
            .foregroundColor(.white)

        HStack(spacing: 20) {
            VStack {
                Circle().fill(theme.statusHealthy).frame(width: 40, height: 40)
                Text("Healthy").font(.caption).foregroundColor(.white)
            }
            VStack {
                Circle().fill(theme.statusWarning).frame(width: 40, height: 40)
                Text("Warning").font(.caption).foregroundColor(.white)
            }
            VStack {
                Circle().fill(theme.statusCritical).frame(width: 40, height: 40)
                Text("Critical").font(.caption).foregroundColor(.white)
            }
            VStack {
                Circle().fill(theme.statusDepleted).frame(width: 40, height: 40)
                Text("Depleted").font(.caption).foregroundColor(.white)
            }
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
    }
}

// MARK: - Update Badge Preview

struct UpdateBadge_Previews: PreviewProvider {
    static var previews: some View {
    let darkTheme = DarkTheme()
    let lightTheme = LightTheme()
    let christmasTheme = ChristmasTheme()

    return HStack(spacing: 40) {
        // Dark mode - default
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(darkTheme.glassBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(darkTheme.textSecondary)
                UpdateBadge()
                    .offset(x: 14, y: -14)
            }
            Text("Dark")
                .font(.caption)
                .foregroundColor(.white)
        }

        // Light mode
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(lightTheme.glassBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(lightTheme.textSecondary)
                UpdateBadge()
                    .offset(x: 14, y: -14)
            }
            .environment(\.colorScheme, .light)
            Text("Light")
                .font(.caption)
                .foregroundColor(.white)
        }

        // Christmas mode
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(christmasTheme.glassBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(christmasTheme.textSecondary)
                UpdateBadge(accentColor: christmasTheme.accentPrimary)
                    .offset(x: 14, y: -14)
            }
            Text("Christmas")
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    .padding(40)
    .background(darkTheme.backgroundGradient)
    }
}

// MARK: - Full Header Preview

struct HeaderSection_Previews: PreviewProvider {
    static var previews: some View {
    let theme = DarkTheme()
    return VStack(spacing: 16) {
        // Header mock
        HStack(spacing: 12) {
            ProviderIconView(providerId: "claude", size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("ClaudeBar")
                    .font(.system(size: 18, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(.white)

                Text("AI Usage Monitor")
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.statusHealthy)
                    .frame(width: 8, height: 8)
                Text("HEALTHY")
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(theme.statusHealthy.opacity(0.25))
            )
        }
        .padding(.horizontal, 16)

        // Provider pills
        HStack(spacing: 8) {
            ProviderPill(providerId: "claude", providerName: "Claude", isSelected: true, hasData: true) {}
            ProviderPill(providerId: "codex", providerName: "Codex", isSelected: false, hasData: true) {}
            ProviderPill(providerId: "gemini", providerName: "Gemini", isSelected: false, hasData: false) {}
            ProviderPill(providerId: "zai", providerName: "Z.ai", isSelected: false, hasData: true) {}
        }
    }
    .padding(.vertical, 20)
    .frame(width: 420)
    .background(theme.backgroundGradient)
    }
}
