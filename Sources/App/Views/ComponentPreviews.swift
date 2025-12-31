import SwiftUI
import Domain

// MARK: - Component Previews
// Preview all UI components in one place

// MARK: - Provider Icons Preview

#Preview("Provider Icons") {
    HStack(spacing: 40) {
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
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Provider Pills Preview

#Preview("Provider Pills") {
    VStack(spacing: 20) {
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
    .background(AppTheme.backgroundGradient(for: .dark))
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
        .background(AppTheme.backgroundGradient(for: .dark))
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
        .background(AppTheme.backgroundGradient(for: .dark))
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
        .background(AppTheme.backgroundGradient(for: .dark))
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
    .background(AppTheme.backgroundGradient(for: .dark))
}

#Preview("Stat Cards - Z.ai Demo") {
    // Z.ai demo mode quotas (matching ZaiDemoUsageProbe data)
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
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Status Badges Preview

#Preview("Status Badges") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            Text("HEALTHY").badge(AppTheme.statusHealthy(for: .dark))
            Text("WARNING").badge(AppTheme.statusWarning(for: .dark))
            Text("LOW").badge(AppTheme.statusCritical(for: .dark))
            Text("EMPTY").badge(AppTheme.statusDepleted(for: .dark))
        }
    }
    .padding(40)
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Action Buttons Preview

#Preview("Action Buttons") {
    HStack(spacing: 12) {
        WrappedActionButton(
            icon: "safari.fill",
            label: "Dashboard",
            gradient: AppTheme.providerGradient(for: "claude", scheme: .dark)
        ) {}

        WrappedActionButton(
            icon: "arrow.clockwise",
            label: "Refresh",
            gradient: AppTheme.accentGradient(for: .dark)
        ) {}

        WrappedActionButton(
            icon: "arrow.clockwise",
            label: "Syncing",
            gradient: AppTheme.accentGradient(for: .dark),
            isLoading: true
        ) {}
    }
    .padding(40)
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Loading Spinner Preview

#Preview("Loading Spinner") {
    LoadingSpinnerView()
        .frame(width: 300)
        .background(AppTheme.backgroundGradient(for: .dark))
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
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Theme Colors Preview

#Preview("Theme Colors") {
    VStack(spacing: 20) {
        Text("Provider Colors")
            .font(.headline)
            .foregroundStyle(.white)

        HStack(spacing: 20) {
            VStack {
                Circle().fill(AppTheme.providerColor(for: "claude", scheme: .dark)).frame(width: 40, height: 40)
                Text("Claude").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(AppTheme.providerColor(for: "codex", scheme: .dark)).frame(width: 40, height: 40)
                Text("Codex").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(AppTheme.providerColor(for: "gemini", scheme: .dark)).frame(width: 40, height: 40)
                Text("Gemini").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(AppTheme.providerColor(for: "zai", scheme: .dark)).frame(width: 40, height: 40)
                Text("Z.ai").font(.caption).foregroundStyle(.white)
            }
        }

        Text("Status Colors")
            .font(.headline)
            .foregroundStyle(.white)

        HStack(spacing: 20) {
            VStack {
                Circle().fill(AppTheme.statusHealthy(for: .dark)).frame(width: 40, height: 40)
                Text("Healthy").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(AppTheme.statusWarning(for: .dark)).frame(width: 40, height: 40)
                Text("Warning").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(AppTheme.statusCritical(for: .dark)).frame(width: 40, height: 40)
                Text("Critical").font(.caption).foregroundStyle(.white)
            }
            VStack {
                Circle().fill(AppTheme.statusDepleted(for: .dark)).frame(width: 40, height: 40)
                Text("Depleted").font(.caption).foregroundStyle(.white)
            }
        }
    }
    .padding(40)
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Update Badge Preview

#Preview("Update Badge") {
    HStack(spacing: 40) {
        // Dark mode - default
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.glassBackground(for: .dark))
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(for: .dark))
                UpdateBadge(isChristmas: false)
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
                    .fill(AppTheme.glassBackground(for: .light))
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary(for: .light))
                UpdateBadge(isChristmas: false)
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
                    .fill(AppTheme.christmasGlassBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.christmasTextSecondary)
                UpdateBadge(isChristmas: true)
                    .offset(x: 14, y: -14)
            }
            Text("Christmas")
                .font(.caption)
                .foregroundStyle(.white)
        }
    }
    .padding(40)
    .background(AppTheme.backgroundGradient(for: .dark))
}

// MARK: - Full Header Preview

#Preview("Header Section") {
    VStack(spacing: 16) {
        // Header mock
        HStack(spacing: 12) {
            ProviderIconView(providerId: "claude", size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("ClaudeBar")
                    .font(AppTheme.titleFont(size: 18))
                    .foregroundStyle(.white)

                Text("AI Usage Monitor")
                    .font(AppTheme.captionFont(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.statusHealthy(for: .dark))
                    .frame(width: 8, height: 8)
                Text("HEALTHY")
                    .font(AppTheme.captionFont(size: 11))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.statusHealthy(for: .dark).opacity(0.25))
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
    .background(AppTheme.backgroundGradient(for: .dark))
}
