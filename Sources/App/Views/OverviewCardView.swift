import SwiftUI
import Domain

/// The *All* page: a two-column grid of cards, one per provider, with the
/// counts above it (docs/features/all-providers/design.md).
struct OverviewPageView: View {
    let overview: Overview
    let open: (OverviewCard) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                if overview.critical > 0 { count("\(overview.critical) critical", theme.statusCritical) }
                if overview.warning > 0 { count("\(overview.warning) warning", theme.statusWarning) }
                if overview.healthy > 0 { count("\(overview.healthy) healthy", theme.statusHealthy) }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(overview.cards) { card in
                    OverviewCardView(card: card) { open(card) }
                }
            }
        }
    }

    private func count(_ text: String, _ color: Color) -> some View {
        Text(text)
            .popoverFont(10, weight: .semibold)
            .foregroundStyle(theme.isOutlined ? theme.textOnStatus : theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(theme.isOutlined ? color : color.opacity(0.18))
                    .overlay(Capsule().stroke(theme.isOutlined ? theme.glassBorder : color.opacity(0.5),
                                              lineWidth: theme.isOutlined ? theme.cardBorderWidth * 0.8 : 1))
            )
    }
}

/// One provider on *All*: its badge, its tightest quota as a ring, the next
/// quota under it. A tap opens the provider's page.
struct OverviewCardView: View {
    let card: OverviewCard
    let open: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ProviderIconView(providerId: card.id, size: 18, showGlow: false)
                    Text(settings.shown(card.name))
                        .popoverFont(12, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    ring
                    VStack(alignment: .leading, spacing: 4) {
                        if let tightest = card.tightest {
                            row(tightest, login: card.tightestLogin)
                            if let next = card.next { row(next, login: nil) }
                        } else {
                            Text(card.badge.badgeText(in: theme).capitalized)
                                .popoverFont(10, weight: .semibold)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Text(card.loginCount > 1 ? "\(card.loginCount) accounts" : " ")
                    Spacer()
                    if card.badge.showsBadge {
                        Text(card.badge.badgeText(in: theme))
                            .foregroundStyle(card.badge.badgeColor(theme))
                    }
                }
                .popoverFont(9, weight: .semibold)
                .foregroundStyle(theme.textTertiary)
            }
            .padding(10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(theme.cardGradient).themeShadow(theme)
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                }
            )
            .contentShape(.rect)
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open \(settings.shown(card.name))")
    }

    /// The tightest quota as a ring; `--` with no numbers.
    private var ring: some View {
        let quota = card.tightest
        let color = quota.map { theme.statusColor(for: $0.status) } ?? theme.textTertiary
        let progress = quota.map { $0.displayProgressPercent(mode: settings.usageDisplayMode) / 100 } ?? 0
        return ZStack {
            Circle()
                .stroke(theme.isOutlined ? theme.progressTrack : theme.textTertiary.opacity(0.3),
                        lineWidth: theme.isOutlined ? 6 : 5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(quota.map(value) ?? "--")
                .popoverDisplayFont(12)
                .foregroundStyle(theme.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(6)
        }
        .frame(width: 48, height: 48)
    }

    private func row(_ quota: UsageQuota, login: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title(quota, login: login))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(value(quota))
            }
            .popoverFont(10, weight: .semibold)
            .foregroundStyle(theme.textPrimary)
            if let reset = quota.resetTimestampDescription ?? quota.resetText {
                Text(reset)
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func title(_ quota: UsageQuota, login: String?) -> String {
        let name = quota.compactTitle ?? quota.quotaType.displayName
        return login.map { "\(settings.shown($0)) · \(name)" } ?? name
    }

    /// A percentage in the person's display mode; a balance as its amount.
    private func value(_ quota: UsageQuota) -> String {
        if quota.percentLeft == nil, let dollars = quota.formattedDollarRemaining { return dollars }
        return "\(Int(quota.displayPercent(mode: settings.usageDisplayMode)))%"
    }
}
