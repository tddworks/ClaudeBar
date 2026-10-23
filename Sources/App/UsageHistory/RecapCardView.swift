import AppKit
import SwiftUI
import Domain
import Diagnostics
import UniformTypeIdentifiers

/// *RECAP* — the week's or month's story across every provider: the total,
/// the split by provider, the top model, the biggest day, what caching saved,
/// and the range before it. A range choice picks the range. It renders what
/// `Recap` says, in the recap's own unit, and never counts; a range that holds
/// nothing says so, and the choice stays while any range has something. The
/// export button writes the recap out as one HTML report, where the person
/// saves it.
struct RecapCardView: View {
    /// Every range the card offers, read by the page.
    let recaps: [RecapRange: Recap]
    /// The dates each recap was read for — what a report writes in its header.
    let dates: [RecapRange: DateRange]
    /// A provider's name, from its id.
    let name: (String) -> String

    @Environment(\.appTheme) private var theme
    @State private var range: RecapRange = .thisWeek
    /// Why the last export failed, if it did — said to the person, not only
    /// to the log.
    @State private var saveError: String?

    var body: some View {
        if recaps.values.contains(where: { !$0.isEmpty }), let recap = recaps[range] {
            card(recap)
        }
    }

    // MARK: - The card

    /// The card for one range: the header, then either its highlights or the
    /// note that the range held nothing.
    @ViewBuilder
    private func card(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            chips
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
        .alert("The report could not be saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .popoverFont(9, weight: .bold)
                    .foregroundStyle(theme.textSecondary)
                Text("RECAP")
                    .popoverFont(8, weight: .medium)
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.3)
            }
            Spacer(minLength: 4)
            if let chosen = recaps[range], !chosen.isEmpty {
                exportButton
            }
        }
    }

    /// The ranges the card offers, as chips.
    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(RecapRange.allCases) { choice in
                chip(choice)
            }
        }
    }

    /// The person's one gesture: the recap written out as an HTML report,
    /// saved where they say, opened when saved.
    private var exportButton: some View {
        Button {
            exportReport()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .popoverFont(9, weight: .medium)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Save as HTML report")
    }

    /// The save panel, the atomic write, the file opened — the report holds
    /// what the card holds; the app never reads it back.
    private func exportReport() {
        guard let recap = recaps[range] else { return }
        let report = RecapHTMLReport(recap: recap, range: range, dates: dates[range], name: name)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Usage recap — \(range.title)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try report.html.write(to: url, atomically: true, encoding: .utf8)
                NSWorkspace.shared.open(url)
            } catch {
                AppLog.ui.error("The recap report could not be written: \(error.localizedDescription)")
                saveError = error.localizedDescription
            }
        }
    }

    /// One range choice, drawn on when it is the one chosen.
    private func chip(_ choice: RecapRange) -> some View {
        let isOn = range == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { range = choice }
        } label: {
            Text(choice.title)
                .font(theme.font(size: 9, weight: isOn ? .bold : .medium))
                .foregroundStyle(isOn ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.controlShape.fill(isOn ? theme.progressTrack : Color.clear))
                .overlay(theme.controlShape.stroke(theme.glassBorder, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    /// The range's total in the recap's unit, and the change against the week
    /// before it.
    private func lead(_ recap: Recap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(UsageFormat.value(recap.total, in: recap.unit))
                .popoverDisplayFont(26)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(recap.unit.caption)
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                Text(subline(recap))
                    .popoverFont(9, weight: .medium)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let change = recap.change {
                changeBadge(UsageFormat.change(change), up: change > 0)
            }
        }
    }

    /// The tokens beside a total in another unit, the time worked and the
    /// sessions — each when the week holds it.
    private func subline(_ recap: Recap) -> String {
        var parts: [String] = []
        if let tokens = recap.tokens { parts.append("\(UsageFormat.count(Int(tokens))) tokens") }
        if recap.workingTime > 0 { parts.append(UsageFormat.duration(recap.workingTime)) }
        if recap.sessions > 0 { parts.append("\(recap.sessions) sessions") }
        return parts.joined(separator: " · ")
    }

    /// The change against the range before, coloured by its direction, over
    /// what it is compared with.
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

    /// The providers the week spans, largest first, each with its total and
    /// share — the sum is never a mystery.
    private func split(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(recap.providers.enumerated()), id: \.element.provider) { index, part in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Self.palette[index % Self.palette.count])
                        .frame(width: 6, height: 6)
                    Text(name(part.provider))
                        .popoverFont(9, weight: .medium)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(UsageFormat.value(part.value, in: recap.unit))
                        .popoverFont(9, weight: .medium)
                        .foregroundStyle(theme.textTertiary)
                    Text(UsageFormat.share(part.share))
                        .popoverFont(9, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
        }
    }

    /// The top model, the biggest day and the cache savings, when the week has
    /// them. The day is written in the person's own locale.
    @ViewBuilder
    private func highlights(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let model = recap.topModel {
                highlight("Top model", Text(model.line.displayName))
            }
            if let day = recap.biggestDay {
                highlight("Biggest day", Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day()))
            }
            if recap.cacheSavings > 0 {
                highlight("Cache saved", Text(UsageFormat.money(recap.cacheSavings)))
            }
        }
    }

    /// One titled line of the highlights.
    private func highlight(_ title: String, _ value: Text) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .popoverFont(8, weight: .medium)
                .foregroundStyle(theme.textTertiary)
            Spacer(minLength: 4)
            value
                .popoverFont(9, weight: .semibold)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
    }

    /// The providers' colours — hues far apart, cycled when the range spans
    /// more providers than the palette holds.
    private static let palette: [Color] = [.purple, .green, .blue, .orange, .pink, .cyan, .indigo, .mint, .red]
}
