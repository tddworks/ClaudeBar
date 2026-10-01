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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                    .font(.system(size: 28, weight: .heavy, design: theme.fontDesign))
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                // Light mode shadow
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(Color.clear)
                        .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
                }

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
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

    // MARK: - Budget Progress Bar

    @ViewBuilder
    private func budgetProgressBar(budget: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.progressTrack)

                    // Fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(budgetProgressGradient)
                        .frame(width: animateProgress ? geo.size.width * budgetPercentUsed / 100 : 0)
                        .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animateProgress)
                }
            }
            .frame(height: 5)

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

    private func formatBudget(_ budget: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
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
