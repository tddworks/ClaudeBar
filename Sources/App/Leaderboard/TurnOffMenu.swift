import SwiftUI
import Domain

/// Where *Turn off ▾* sits in the popover, so the popover's top layer can
/// draw its menu just above it, outside the scroll view that would clip it.
struct TurnOffAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// *TURN OFF ▾* — the Leaderboard tab's one way out: your country off the
/// globe (while it's on), the whole Leaderboard paused and hidden, or
/// leaving, set apart. A card in the current theme, as the mockup draws it.
struct TurnOffMenu: View {
    let leaderboard: Leaderboard
    /// *Leave and delete my data…*: confirmed in Settings → Leaderboard.
    let onLeave: () -> Void

    @Environment(\.appTheme) private var theme

    private var membership: LeaderboardMembership { leaderboard.membership }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if membership.sharesCountry {
                TurnOffMenuItem(title: "My country on the globe", detail: "The server forgets it at once.") {
                    leaderboard.closeTurnOffMenu()
                    Task { try? await membership.setSharesCountry(false) }
                }
            }
            TurnOffMenuItem(title: "Leaderboard: pause & hide",
                            detail: "Stops uploads, hides this tab. Your name and days stay.") {
                withAnimation(.easeInOut(duration: 0.2)) { leaderboard.turnOff() }
            }
            Line()
                .stroke(theme.glassBorder.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 1.5)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            TurnOffMenuItem(title: "Leave and delete my data…",
                            detail: "Removes your name and every day from the server.", isDestructive: true) {
                leaderboard.closeTurnOffMenu()
                onLeave()
            }
        }
        .padding(6)
        .frame(width: 250)
        .background(
            // A glass theme's card is see-through: the popover's own
            // background under it keeps the board rows from showing through.
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.backgroundGradient)
                .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).fill(theme.cardGradient))
                .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
                // One shape casts the shadow: without it the border casts
                // its own, drawn inside the card as a second outline.
                .compositingGroup()
                .themeShadow(theme, scale: 0.8)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Turn off")
    }
}

private struct TurnOffMenuItem: View {
    let title: String
    let detail: String
    var isDestructive = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(theme.font(size: 12, weight: .bold))
                    .foregroundStyle(isDestructive ? theme.statusCritical : theme.textPrimary)
                Text(detail)
                    .font(theme.font(size: 10))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(isHovering ? theme.accentPrimary.opacity(0.15) : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityHint(detail)
    }
}

/// A straight line across its frame, for the dashed divider.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}
