import SwiftUI
import Domain

/// A card that displays cost-based usage data for Claude accounts.
/// Shows total cost, optional budget progress, and reset time for Pro Extra usage.
struct CostStatCard: View {
    let costUsage: CostUsage
    let externalBudget: Decimal?
    let delay: Double

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var animateProgress = false

    init(costUsage: CostUsage, budget: Decimal? = nil, delay: Double = 0) {
        self.costUsage = costUsage
        self.externalBudget = budget
        self.delay = delay
    }

    /// Extra usage uses only its server-provided monthly cap. API cost can
    /// fall back to the budget configured in settings.
    private var effectiveBudget: Decimal? {
        switch costUsage.kind {
        case .extraUsage:
            costUsage.budget
        case .apiCost:
            costUsage.budget ?? externalBudget
        }
    }

    private var effectiveBudgetRemaining: Decimal? {
        if let remaining = costUsage.budgetRemaining {
            return remaining
        }
        guard let externalBudget else { return nil }
        return max(0, externalBudget - costUsage.totalCost)
    }

    private var headerTitle: String {
        switch costUsage.kind {
        case .apiCost:
            "API COST"
        case .extraUsage:
            "EXTRA USAGE"
        }
    }

    private var budgetStatus: BudgetStatus? {
        guard let budget = effectiveBudget, budget > 0 else { return nil }
        return costUsage.budgetStatus(budget: budget)
    }

    private var budgetPercentUsed: Double {
        guard let budget = effectiveBudget, budget > 0 else { return 0 }
        return min(100, costUsage.budgetPercentUsed(budget: budget))
    }

    /// An outlined theme (Pop) prints a budgeted spend its own way: amount
    /// left, budget right, the card's name on a sticker.
    private var printedBudget: Decimal? {
        guard theme.isOutlined, let budget = effectiveBudget, budget > 0 else { return nil }
        return budget
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let budget = printedBudget {
                printedHeader(budget: budget)
                QuotaProgressBar(
                    percent: budgetPercentUsed,
                    fill: theme.accentPrimary,
                    animate: animateProgress,
                    delay: delay
                )
            } else {
                standardHeader
            }

            details
        }
        .padding(12)
        .padding(.top, printedBudget == nil ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient).themeShadow(theme)

                if printedBudget != nil {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(theme.accentPrimary.opacity(0.16))
                }

                // Light mode shadow
                if colorScheme == .light && !theme.isOutlined {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(Color.clear)
                        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
                }

                // An outlined theme inks its cards solid, like every other card.
                if theme.isOutlined {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                } else {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(cardBorderGradient, lineWidth: 1)
                }
            }
        )
        .overlay(alignment: .topTrailing) {
            if printedBudget != nil {
                sticker.offset(x: -12, y: -9)
            }
        }
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear {
            animateProgress = true
        }
    }

    // MARK: - Printed (outlined theme)

    /// "SPENT THIS MONTH / $12.40" on the left; "of your budget / $50.00 /
    /// On track" on the right.
    private func printedHeader(budget: Decimal) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(QuotaCardText.spentLabel(for: costUsage.kind))
                    .font(.system(size: 8, weight: .heavy, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .tracking(0.6)
                OutlinedNumber(text: costUsage.formattedCost, size: 26, color: theme.accentPrimary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("of your budget")
                    .font(.system(size: 9, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                Text(formatBudget(budget, cents: true))
                    .font(theme.displayFont(size: 14))
                    .foregroundStyle(theme.textPrimary)
                if let status = budgetStatus {
                    Text(QuotaCardText.budgetPhrase(status))
                        .font(.system(size: 9, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    /// The card's name on a tilted, dashed sticker over its top edge.
    private var sticker: some View {
        Text(headerTitle)
            .font(.system(size: 8.5, weight: .heavy, design: theme.fontDesign))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.statusWarning))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.glassBorder, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            )
            .background(
                RoundedRectangle(cornerRadius: 6).fill(theme.glassBorder).offset(x: 2, y: 2)
            )
            .rotationEffect(.degrees(-5))
            .fixedSize()
    }

    // MARK: - Standard

    @ViewBuilder
    private var standardHeader: some View {
        // Header row with icon and status badge
        HStack(alignment: .top, spacing: 0) {
            // Left side: icon and label
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(budgetStatusColor)

                Text(headerTitle)
                    .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }

            Spacer(minLength: 4)

            // Status badge
            if let status = budgetStatus {
                Text(status.badgeText)
                    .badge(theme.statusColor(for: status.toQuotaStatus))
            }
        }

        // Large cost display
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(costUsage.formattedCost)
                .font(theme.displayFont(size: 28, weight: .heavy))
                .foregroundStyle(theme.textPrimary)

            if let budget = effectiveBudget {
                Text("of \(formatBudget(budget))")
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        }

        // Budget progress bar (if budget is set)
        if let budget = effectiveBudget, budget > 0 {
            budgetProgressBar(budget: budget)
        } else if costUsage.kind == .extraUsage, effectiveBudget == nil {
            Text("No monthly cap")
                .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// A spend's parts and its time, under either header.
    @ViewBuilder
    private var details: some View {
        // Its parts — a model's share of the day — largest first
        if !costUsage.lines.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(costUsage.lines.prefix(3).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Text(line.label)
                            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(line.formattedAmount)
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .help(line.detail ?? line.label)
                }
                if costUsage.lines.count > 3 {
                    Text("and \(costUsage.lines.count - 3) more")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        // Show API Duration if > 0, or reset time for Pro Extra usage
        if costUsage.apiDuration > 0 {
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 7))

                Text("API Time: \(costUsage.formattedApiDuration)")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            }
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
        } else if let resetText = costUsage.resetText {
            HStack(spacing: 3) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 7))

                Text(resetText)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            }
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
        }
    }

    // MARK: - Budget Progress Bar

    @ViewBuilder
    private func budgetProgressBar(budget: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            QuotaProgressBar(
                percent: budgetPercentUsed,
                fill: budgetProgressGradient,
                animate: animateProgress,
                delay: delay
            )

            // Budget label
            if let remaining = effectiveBudgetRemaining {
                HStack {
                    Text("\(Int(budgetPercentUsed))% used · \(formatBudget(remaining)) left")
                        .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)

                    Spacer()
                }
            }
        }
    }

    // MARK: - Styling

    private var budgetStatusColor: Color {
        guard let status = budgetStatus else { return theme.statusHealthy }
        return theme.statusColor(for: status.toQuotaStatus)
    }

    private var budgetProgressGradient: LinearGradient {
        guard let status = budgetStatus else {
            return LinearGradient(colors: [theme.statusHealthy], startPoint: .leading, endPoint: .trailing)
        }

        let color = theme.statusColor(for: status.toQuotaStatus)
        return LinearGradient(
            colors: [color.opacity(0.8), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardBorderGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.glassBorder.opacity(isHovering ? 1.2 : 1.0),
                theme.glassBorder.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func formatBudget(_ budget: Decimal, cents: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = cents ? 2 : 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: budget as NSDecimalNumber) ?? "$\(budget)"
    }
}

// MARK: - Preview

#Preview("Extra Usage - Capped Zero") {
    ZStack {
        DarkTheme().backgroundGradient

        CostStatCard(
            costUsage: CostUsage(
                totalCost: 0,
                budget: 500,
                apiDuration: 0,
                providerId: "claude",
                kind: .extraUsage
            )
        )
        .padding()
    }
    .frame(width: 380, height: 180)
    .preferredColorScheme(.dark)
}

#Preview("Extra Usage - Capped Partial") {
    ZStack {
        LightTheme().backgroundGradient

        CostStatCard(
            costUsage: CostUsage(
                totalCost: 5.41,
                budget: 20,
                apiDuration: 0,
                providerId: "claude",
                kind: .extraUsage,
                resetText: "Resets Jan 1, 2026"
            )
        )
        .padding()
    }
    .frame(width: 380, height: 200)
    .preferredColorScheme(.light)
}

#Preview("Extra Usage - Uncapped Spent") {
    ZStack {
        DarkTheme().backgroundGradient

        CostStatCard(
            costUsage: CostUsage(
                totalCost: Decimal(string: "1234.56")!,
                apiDuration: 0,
                providerId: "claude",
                kind: .extraUsage
            )
        )
        .padding()
    }
    .frame(width: 380, height: 160)
    .preferredColorScheme(.dark)
}

#Preview("API Cost") {
    ZStack {
        DarkTheme().backgroundGradient

        CostStatCard(
            costUsage: CostUsage(
                totalCost: 0.55,
                apiDuration: 379.7,
                providerId: "claude"
            ),
            budget: 10
        )
        .padding()
    }
    .frame(width: 380, height: 200)
    .preferredColorScheme(.dark)
}
