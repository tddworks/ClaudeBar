import SwiftUI
import Domain

/// The *All* page: a two-column grid of cards, one per provider, with the
/// counts above it (docs/features/monitoring/all-providers/design.md).
struct OverviewPageView: View {
    let overview: Overview
    let open: (OverviewCard) -> Void

    var body: some View {
        VStack(spacing: 10) {
            OverviewCounts(overview: overview)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(overview.cards) { card in
                    OverviewCardView(card: card) { open(card) }
                }
            }
        }
    }
}

/// The *All* page in **Bars**: a row per provider, a line per quota the
/// person watches, every bar drawn from the same place so two providers can be
/// read against each other down the column (docs/features/monitoring/all-providers/design.md).
struct OverviewBarsPageView: View {
    let overview: Overview
    let open: (OverviewCard) -> Void

    var body: some View {
        VStack(spacing: 10) {
            OverviewCounts(overview: overview)
            VStack(spacing: 8) {
                ForEach(overview.cards) { card in
                    OverviewBarRowView(card: card) { open(card) }
                }
            }
        }
    }
}

/// The critical / warning / healthy capsules both styles show above the page.
private struct OverviewCounts: View {
    let overview: Overview

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if overview.critical > 0 { count("\(overview.critical) critical", theme.statusCritical) }
            if overview.warning > 0 { count("\(overview.warning) warning", theme.statusWarning) }
            if overview.healthy > 0 { count("\(overview.healthy) healthy", theme.statusHealthy) }
            Spacer(minLength: 0)
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

/// One provider in **Bars**: its word, then one line per quota it watches.
/// A tap opens the provider's page, as a card does.
struct OverviewBarRowView: View {
    let card: OverviewCard
    let open: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    ProviderIconView(providerId: card.id, size: 16, showGlow: false)
                    Text(settings.shown(card.name))
                        .popoverFont(11, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let account = card.tightestLogin {
                        Text(settings.shown(account))
                            .popoverFont(9, weight: .medium)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if card.badge.showsBadge {
                        Text(card.badge.badgeText(in: theme))
                            .popoverFont(9, weight: .semibold)
                            .foregroundStyle(card.badge.badgeColor(theme))
                    }
                }
                if card.lines.isEmpty {
                    Text(card.badge.badgeText(in: theme).capitalized)
                        .popoverFont(10, weight: .semibold)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    // Keyed by the quota, not the row's offset: a refresh can
                    // reorder lines, and identity by position would hand one
                    // line's view to another quota's content.
                    ForEach(Array(card.lines.enumerated()), id: \.element.quotaType) { index, quota in
                        OverviewQuotaLineView(quota: quota, delay: Double(index) * 0.05)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(theme.cardGradient).themeShadow(theme)
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                }
            )
            .contentShape(.rect)
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Open \(settings.shown(card.name))")
    }
}

/// One quota in a **Bars** row: its label and reset on the left, its bar in
/// the fixed middle, its percentage on the right. The label and the number
/// are held at a fixed width so every bar on the page starts and ends in the
/// same place — that is what makes two providers comparable.
private struct OverviewQuotaLineView: View {
    let quota: UsageQuota
    let delay: Double

    @Environment(\.appTheme) private var theme
    @Environment(\.popoverTextSize) private var popoverTextSize
    @State private var settings = AppSettings.shared

    /// Held columns so every bar on the page starts and ends in the same
    /// place. They scale with the popover's text size, which widens the
    /// popover by the same factor — the bar keeps its share of the row.
    private var labelWidth: CGFloat { popoverTextSize.scaled(82) }
    private var valueWidth: CGFloat { popoverTextSize.scaled(46) }

    var body: some View {
        HStack(spacing: 8) {
            label
                .frame(width: labelWidth, alignment: .leading)
            bar
                .frame(maxWidth: .infinity)
            value
                .frame(width: valueWidth, alignment: .trailing)
        }
        // A minimum, not a height: the label is two lines when a quota has a
        // reset, and at a larger text size a fixed height would compress them.
        .frame(minHeight: 20)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .popoverFont(10, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            // The line's countdown stays in two units — `resetDescription`
            // caps itself there — so "2d 1h" fits the held column that the
            // full "Resets in 1d 18h 59m" would spill out of.
            if let reset = quota.resetDescription ?? quota.resetText {
                Text(reset)
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
        // The name is what tells two quotas apart, so it stays readable when
        // the column has to cut it.
        .help(title)
    }

    /// The page's own bar, on the mode the person chose. A balance with no
    /// ceiling has no percentage, so it gets no bar rather than a false one.
    @ViewBuilder
    private var bar: some View {
        if !quota.isBalance {
            QuotaCardBar(quota: quota, delay: delay)
        }
    }

    /// A percentage in the person's display mode; a balance as its amount.
    private var value: some View {
        Text(text)
            .popoverDisplayFont(11)
            .foregroundStyle(theme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var text: String { QuotaLineText.value(quota, mode: settings.usageDisplayMode) }

    private var title: String { QuotaLineText.title(quota) }
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
        QuotaLineText.title(quota, login: login, shown: { settings.shown($0) })
    }

    /// A percentage in the person's display mode; a balance as its amount.
    private func value(_ quota: UsageQuota) -> String {
        QuotaLineText.value(quota, mode: settings.usageDisplayMode)
    }
}
