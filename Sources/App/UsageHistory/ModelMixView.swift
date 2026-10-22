import SwiftUI
import Domain

/// *MODEL MIX — LAST YEAR* — which models a login actually leans on over a
/// range: one bar split by model, and a row each, largest first. Everything it
/// says, `ModelMix` answers, read in the range's opening unit.
struct ModelMixView: View {
    let days: Days
    /// The card's heading, in the page's words.
    var title: String = "MODEL MIX — LAST YEAR"

    @Environment(\.appTheme) private var theme

    /// The unit the card reads the range in: the one it opens on.
    private var unit: Days.Unit { days.defaultUnit }
    private var mix: ModelMix { ModelMix(of: days, in: unit) }

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
                Text(UsageFormat.value(days.total(in: unit), in: unit))
                    .font(theme.displayFont(size: 13))
                    .foregroundStyle(theme.textPrimary)
                Text(unit.caption)
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
                ForEach(mix.parts, id: \.line.model) { part in
                    Rectangle()
                        .fill(ModelColors.color(of: part.line.model, in: days))
                        .frame(width: proxy.size.width * part.share)
                }
            }
        }
        .frame(height: 8)
        .background(theme.progressTrack)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(mix.parts, id: \.line.model) { part in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ModelColors.color(of: part.line.model, in: days))
                        .frame(width: 6, height: 6)
                    Text(part.line.displayName)
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(UsageFormat.value(part.value, in: unit))
                        .font(theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(UsageFormat.share(part.share))
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
    }
}