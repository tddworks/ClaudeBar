import SwiftUI
import Domain

/// *MODEL MIX — LAST YEAR* — which models a login actually leans on over a
/// range: one bar split by model, and a row each, largest first. Everything it
/// says, `Days.byModel` and `Days.share(of:)` answer.
struct ModelMixView: View {
    let days: Days
    /// The card's heading, in the page's words.
    var title: String = "MODEL MIX — LAST YEAR"

    @Environment(\.appTheme) private var theme

    private var mix: [ModelUsageLine] { days.byModel }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            bar
            rows
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple)
                Text(title)
                    .font(theme.font(size: 8, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(unit(days.total))
                    .font(theme.displayFont(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Text(days.unit == .cost ? "spent" : "tokens")
                    .font(theme.font(size: 8, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    // MARK: - The mix

    /// The range as one bar: a part a model, in the colours the chart gives it.
    private var bar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(mix, id: \.model) { line in
                    Rectangle()
                        .fill(ModelColors.color(of: line.model, in: days))
                        .frame(width: proxy.size.width * days.share(of: line))
                }
            }
        }
        .frame(height: 8)
        .background(theme.progressTrack)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(mix, id: \.model) { line in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ModelColors.color(of: line.model, in: days))
                        .frame(width: 6, height: 6)
                    Text(ModelUsageLine.displayName(line.model))
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(unit(days.value(of: line)))
                        .font(theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(UsageFormat.share(days.share(of: line)))
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }

    /// The value in the unit the range is read in — money, or tokens.
    private func unit(_ value: Double) -> String {
        days.unit == .cost ? UsageFormat.money(Decimal(value)) : UsageFormat.count(Int(value))
    }
}