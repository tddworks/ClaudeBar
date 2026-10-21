import SwiftUI
import Domain

/// *WEEKLY RECAP* — the week's story across every provider: the total, the
/// split by provider, the top model, the biggest day, what caching saved, and
/// the week before it. A range choice picks the week. It renders what `Recap`
/// says and never counts; a week that holds nothing says so, and the choice
/// stays reachable as long as either week has something.
struct RecapCardView: View {
    let monitor: QuotaMonitor
    var calendar: Calendar = DataSources.calendar()

    @Environment(\.appTheme) private var theme
    @State private var range: RecapRange = .thisWeek

    var body: some View {
        let thisWeek = recap(of: .thisWeek)
        let lastWeek = recap(of: .lastWeek)
        if !thisWeek.isEmpty || !lastWeek.isEmpty {
            card(range == .thisWeek ? thisWeek : lastWeek)
        }
    }

    /// The recap of a range, built from every login's days as they were read.
    private func recap(of range: RecapRange) -> Recap {
        RecapBuilder.build(logins, in: range.range(containing: Date(), calendar: calendar), calendar: calendar)
    }

    /// Every login's days, already read — the thirty days the login keeps. A
    /// login with none is left out; the days themselves are the record.
    private var logins: [RecapLogin] {
        monitor.lineup.compactMap { login in
            login.usageHistory?.lastThirtyDays.map { RecapLogin(providerId: login.providerId, days: $0) }
        }
    }

    // MARK: - The card

    @ViewBuilder
    private func card(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if recap.isEmpty {
                Text(range.emptyNote)
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
            } else {
                lead(recap)
                split(recap)
                highlights(recap)
            }
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

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .popoverFont(9, weight: .bold)
                    .foregroundStyle(theme.textSecondary)
                Text("WEEKLY RECAP")
                    .popoverFont(8, weight: .medium)
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                ForEach(RecapRange.allCases) { choice in
                    chip(choice)
                }
            }
        }
    }

    private func chip(_ choice: RecapRange) -> some View {
        let isOn = range == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { range = choice }
        } label: {
            Text(choice.rawValue)
                .font(theme.font(size: 9, weight: isOn ? .bold : .medium))
                .foregroundStyle(isOn ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.controlShape.fill(isOn ? theme.progressTrack : Color.clear))
                .overlay(theme.controlShape.stroke(theme.glassBorder, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    /// The range's total, in the unit in force, and the comparison with the
    /// range before it.
    private func lead(_ recap: Recap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(recap.knowsCost ? recap.formattedCost : recap.formattedTokens)
                .popoverDisplayFont(26)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(recap.knowsCost ? "spent" : "tokens")
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                Text(subline(recap))
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let change = recap.formattedChange {
                changeBadge(change, up: (recap.changePercent ?? 0) > 0)
            }
        }
    }

    private func subline(_ recap: Recap) -> String {
        var parts: [String] = []
        if recap.knowsCost { parts.append("\(recap.formattedTokens) tokens") }
        if recap.totals.workingTime > 0 { parts.append(recap.formattedWorkingTime) }
        if recap.totals.sessions > 0 { parts.append("\(recap.totals.sessions) sessions") }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }

    private func changeBadge(_ change: String, up: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(change)
                .popoverFont(11, weight: .bold)
                .foregroundStyle(up ? .orange : .green)
            Text(range.comparedWith)
                .popoverFont(7, weight: .medium)
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// The providers the range spans, largest first — the sum is never a
    /// mystery.
    private func split(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(recap.providers.enumerated()), id: \.element.id) { index, provider in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.palette[index % Self.palette.count])
                        .frame(width: 6, height: 6)
                    Text(name(of: provider.provider))
                        .popoverFont(9, weight: .medium)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(recap.formattedShare(of: provider))
                        .popoverFont(9, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func highlights(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let model = recap.topModel {
                highlight("Top model", model.displayName)
            }
            if let day = recap.biggestDay {
                highlight("Biggest day", day.formattedDate)
            }
            if recap.cacheSavings > 0 {
                highlight("Cache saved", recap.formattedSavings)
            }
        }
    }

    private func highlight(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .popoverFont(8, weight: .medium)
                .foregroundStyle(theme.textTertiary)
            Spacer(minLength: 4)
            Text(value)
                .popoverFont(9, weight: .semibold)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
    }

    /// The providers' colours — hues far apart, cycled when the range spans
    /// more providers than the palette holds.
    private static let palette: [Color] = [.purple, .green, .blue, .orange, .pink, .cyan, .indigo, .mint, .red]

    private func name(of provider: String) -> String {
        monitor.providers.provider(id: provider)?.name ?? provider.capitalized
    }
}