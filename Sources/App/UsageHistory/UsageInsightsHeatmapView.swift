import SwiftUI
import Domain

/// *USAGE — LAST YEAR* — a range of a login's days as a heatmap: a cell a day,
/// shaded by how full it is against the range's busiest, an empty day an empty
/// cell. Everything it says, `Days.byDay` answers.
struct UsageInsightsHeatmapView: View {
    let days: Days
    /// The card's heading, in the page's words.
    var title: String = "USAGE — LAST YEAR"

    @Environment(\.appTheme) private var theme
    @Environment(\.popoverTextSize) private var popoverTextSize

    /// The gap between cells, and between the weeks' columns.
    private let gap: CGFloat = 1.5
    /// The page's and this card's own horizontal padding, which the grid gives up.
    private let horizontalInsets: CGFloat = 16 * 2 + 12 * 2

    /// The cell's side for a laid-out heatmap: a year of columns shares the
    /// width the card has, so the heatmap never runs past the popover and
    /// never scrolls.
    private func cellSide(for heatmap: UsageHeatmap) -> CGFloat {
        let columns = max(heatmap.weeks.count, 1)
        let room = popoverTextSize.popoverWidth - horizontalInsets - gap * CGFloat(columns - 1)
        return max(3.5, min(12, room / CGFloat(columns)))
    }

    var body: some View {
        // Laid out and sized once, so a year's cells never rebuild the
        // heatmap for each of them.
        let heatmap = UsageHeatmap(days.byDay)
        let cell = cellSide(for: heatmap)
        return VStack(alignment: .leading, spacing: 8) {
            header
            monthRow(heatmap, cell: cell)
            grid(heatmap, cell: cell)
            legend
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
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
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
                if days.cacheSavings > 0 {
                    Text("Saved \(days.formattedCacheSavings) by caching")
                        .font(theme.font(size: 8, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    // MARK: - The grid

    /// The month each column starts, above it.
    private func monthRow(_ heatmap: UsageHeatmap, cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: gridWidth, height: 10)
            ForEach(heatmap.monthMarks, id: \.month) { mark in
                Text(Self.monthFormat.string(from: mark.month))
                    .font(theme.font(size: 7, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize()
                    .offset(x: CGFloat(mark.column) * (cell + gap))
            }
        }
        .frame(width: gridWidth, height: 10, alignment: .topLeading)
    }

    private func grid(_ heatmap: UsageHeatmap, cell: CGFloat) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(heatmap.weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cellView(day, cell: cell)
                    }
                }
            }
        }
    }

    /// One day's cell: its shade, sized `cell`; a day with nothing an empty
    /// cell, never a gap.
    @ViewBuilder
    private func cellView(_ day: DayValue?, cell: CGFloat) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(shade(day.level))
                .frame(width: cell, height: cell)
                .help("\(Self.dayFormat.string(from: day.date)) · \(unit(day.value))")
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private var legend: some View {
        HStack(spacing: 3) {
            Spacer(minLength: 0)
            Text("less")
                .font(theme.font(size: 8, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(shade(level))
                    .frame(width: 6, height: 6)
            }
            Text("more")
                .font(theme.font(size: 8, weight: .medium))
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// The width the grid has: the popover, less the page's and this card's
    /// own horizontal padding.
    private var gridWidth: CGFloat {
        popoverTextSize.popoverWidth - horizontalInsets
    }

    /// A day's shade — how full it is, from `DayValue.level`; the palette is
    /// the page's.
    private func shade(_ level: Int) -> Color {
        switch level {
        case 0: theme.progressTrack
        case 1: Color.green.opacity(0.25)
        case 2: Color.green.opacity(0.45)
        case 3: Color.green.opacity(0.7)
        default: Color.green
        }
    }

    private func unit(_ value: Double) -> String {
        days.unit == .cost ? UsageFormat.money(Decimal(value)) : UsageFormat.count(Int(value))
    }

    private static let monthFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}