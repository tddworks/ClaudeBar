import SwiftUI
import Kit

// MARK: - Component Previews
// Preview all UI components in one place

// MARK: - Provider Icons Preview

#Preview("Provider Icons") {
    let theme = DarkTheme()
    return HStack(spacing: 40) {
        VStack(spacing: 8) {
            ProviderIconView(providerId: "claude", size: 32)
            Text("Claude")
                .font(.caption)
                .foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ProviderIconView(providerId: "codex", size: 32)
            Text("Codex")
                .font(.caption)
                .foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ProviderIconView(providerId: "gemini", size: 32)
            Text("Gemini")
                .font(.caption)
                .foregroundStyle(.white)
        }
        VStack(spacing: 8) {
            ProviderIconView(providerId: "zai", size: 32)
            Text("Z.ai")
                .font(.caption)
                .foregroundStyle(.white)
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
}

// MARK: - Provider Pills Preview

#Preview("Provider Pills") {
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

// MARK: - Stat Cards Preview

#Preview("Stat Cards - Healthy") {
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

#Preview("Stat Cards - Warning") {
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

#Preview("Stat Cards - Critical") {
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

#Preview("Stat Cards Grid") {
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

#Preview("Stat Cards - Z.ai") {
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

// MARK: - Status Badges Preview

#Preview("Status Badges") {
    let theme = DarkTheme()
    return VStack(spacing: 16) {
        HStack(spacing: 12) {
            Text("HEALTHY").badge(theme.statusHealthy)
            Text("WARNING").badge(theme.statusWarning)
            Text("LOW").badge(theme.statusCritical)
            Text("EMPTY").badge(theme.statusDepleted)
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
}

// MARK: - Action Buttons Preview

#Preview("Action Buttons") {
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

// MARK: - Loading Spinner Preview

#Preview("Loading Spinner") {
    LoadingSpinnerView()
        .frame(width: 300)
        .background(DarkTheme().backgroundGradient)
}

// MARK: - Glass Card Preview

#Preview("Glass Cards") {
    VStack(spacing: 16) {
        Text("Glass Card Style")
            .font(.headline)
            .foregroundStyle(.white)
            .glassCard()

        HStack {
            Image(systemName: "person.circle.fill")
            Text("user@example.com")
            Spacer()
            Text("Just now")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .glassCard(cornerRadius: 12, padding: 10)
    }
    .padding(40)
    .frame(width: 300)
    .background(DarkTheme().backgroundGradient)
}

// MARK: - Theme Colors Preview

#Preview("Theme Colors") {
    let theme = DarkTheme()
    return VStack(spacing: 20) {
        Text("Provider Colors")
            .font(.headline)
            .foregroundStyle(.white)

        HStack(spacing: 20) {
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "claude", scheme: .dark)).frame(width: 40, height: 40)
                Text("Claude").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "codex", scheme: .dark)).frame(width: 40, height: 40)
                Text("Codex").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "gemini", scheme: .dark)).frame(width: 40, height: 40)
                Text("Gemini").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(ProviderVisualIdentityLookup.color(for: "zai", scheme: .dark)).frame(width: 40, height: 40)
                Text("Z.ai").font(.caption).foregroundStyle(.white)
            }
        }

        Text("Status Colors")
            .font(.headline)
            .foregroundStyle(.white)

        HStack(spacing: 20) {
            VStack {
                Circle().fill(theme.statusHealthy).frame(width: 40, height: 40)
                Text("Healthy").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(theme.statusWarning).frame(width: 40, height: 40)
                Text("Warning").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(theme.statusCritical).frame(width: 40, height: 40)
                Text("Critical").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(theme.statusDepleted).frame(width: 40, height: 40)
                Text("Depleted").font(.caption).foregroundStyle(.white)
            }
        }
    }
    .padding(40)
    .background(theme.backgroundGradient)
}

// MARK: - Update Badge Preview

#Preview("Update Badge") {
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
                    .foregroundStyle(darkTheme.textSecondary)
                UpdateBadge()
                    .offset(x: 14, y: -14)
            }
            Text("Dark")
                .font(.caption)
                .foregroundStyle(.white)
        }

        // Light mode
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(lightTheme.glassBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(lightTheme.textSecondary)
                UpdateBadge()
                    .offset(x: 14, y: -14)
            }
            .environment(\.colorScheme, .light)
            Text("Light")
                .font(.caption)
                .foregroundStyle(.white)
        }

        // Christmas mode
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(christmasTheme.glassBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(christmasTheme.textSecondary)
                UpdateBadge(accentColor: christmasTheme.accentPrimary)
                    .offset(x: 14, y: -14)
            }
            Text("Christmas")
                .font(.caption)
                .foregroundStyle(.white)
        }
    }
    .padding(40)
    .background(darkTheme.backgroundGradient)
}

// MARK: - Full Header Preview

#Preview("Header Section") {
    let theme = DarkTheme()
    return VStack(spacing: 16) {
        // Header mock
        HStack(spacing: 12) {
            ProviderIconView(providerId: "claude", size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("ClaudeBar")
                    .font(theme.font(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text("AI Usage Monitor")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.statusHealthy)
                    .frame(width: 8, height: 8)
                Text("HEALTHY")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
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
