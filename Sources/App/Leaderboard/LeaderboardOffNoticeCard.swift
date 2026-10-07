import SwiftUI

/// Said once in the popover after the Leaderboard was turned off there:
/// what happened, where to turn it back on, and Undo.
struct LeaderboardOffNoticeCard: View {
    let notice: LeaderboardOffNotice
    let onUndo: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Text(notice.text)
                .font(theme.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onUndo) {
                Text("Undo")
                    .font(theme.font(size: 11, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(theme.glassBackground))
                    .overlay(Capsule().stroke(theme.glassBorder, lineWidth: max(1, theme.cardBorderWidth * 0.6)))
            }
            .buttonStyle(.plain)
            .help("Turn the Leaderboard back on")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.statusWarning.opacity(0.28))
                .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
        )
        .accessibilityElement(children: .combine)
    }
}
