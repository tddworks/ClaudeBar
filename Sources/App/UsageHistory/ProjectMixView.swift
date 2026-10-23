import SwiftUI
import Domain

/// *PROJECTS — LAST YEAR* — where a login's work went over a range: one bar
/// split by project, and a row each, largest first. Everything it says,
/// `ByProject` answers, read in the range's opening unit; it shows only when
/// the range names a project, never as a split of one unnamed part.
struct ProjectMixView: View {
    let days: Days
    /// The card's heading, in the page's words.
    var title: String = "PROJECTS — LAST YEAR"

    @Environment(\.appTheme) private var theme

    /// The unit the card reads the range in: the one it opens on.
    /// The card reads the range in the unit it opens on — the one its caption names.
    private var unit: Days.Unit { days.defaultUnit }
    /// The range's project split, answered once per body and handed to its parts.
    private var byProject: ByProject { ByProject(of: days, in: unit) }

    /// The card: header, the one bar, and a row per project.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let split = byProject
            header
            bar(split)
            rows(split)
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
                Image(systemName: "folder.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.teal)
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

    // MARK: - The split

    /// The range as one bar: a part a project, in the colours of the range.
    private func bar(_ split: ByProject) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(split.parts, id: \.line.project) { part in
                    Rectangle()
                        .fill(ModelColors.color(ofProject: part.line.project, in: split))
                        .frame(width: proxy.size.width * part.share)
                }
            }
        }
        .frame(height: 8)
        .background(theme.progressTrack)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func rows(_ split: ByProject) -> some View {
        VStack(spacing: 4) {
            ForEach(split.parts, id: \.line.project) { part in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ModelColors.color(ofProject: part.line.project, in: split))
                        .frame(width: 6, height: 6)
                    Text(part.line.displayName)
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
