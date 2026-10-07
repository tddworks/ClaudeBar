import SwiftUI
import Kit

/// The one Claude Code card in the menu popover.
///
/// A single session shows as `SessionIndicatorView`. Several sessions share
/// one card of fixed maximum height: a row per session with its state, most
/// pressing first, folded into "+N more" past `maxRows`. Since the order is by
/// prominence, what gets folded is the stopped sessions — with many terminals
/// open they are the bulk, and a row each would push the quota cards off screen.
struct SessionsCardView: View {
    let sessionMonitor: SessionMonitor

    /// How many session rows the card shows before folding the rest into "+N more".
    static let maxRows = 5

    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        // The durations read the clock, which no observable change drives;
        // ticking once a second keeps them moving while the popover is open.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if sessionMonitor.sessions.count == 1, let session = sessionMonitor.activeSession {
                SessionIndicatorView(session: session)
            } else {
                manySessions
            }
        }
    }

    // MARK: - Several sessions

    private var manySessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("\(sessionMonitor.sessions.count) sessions")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Spacer()
            }

            ForEach(shownSessions) { session in
                sessionRow(session)
            }

            if hiddenRowCount > 0 {
                Text(hiddenRowsLabel)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, 18)
            }
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient).themeShadow(theme)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(borderColor.opacity(0.3), lineWidth: 1)
            }
        )
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.phase.color)
                .frame(width: 8, height: 8)

            Text(session.repoName)
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            Text(session.phase.label)
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(session.phase.color)

            Spacer()

            if session.completedTaskCount > 0 {
                Label("\(session.completedTaskCount)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }

            if session.activeSubagentCount > 0 {
                Label("\(session.activeSubagentCount)", systemImage: "person.2.fill")
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }

            Text(session.durationDescription)
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - What the card shows

    /// Every session gets a row, most pressing first.
    private var rowSessions: [Session] {
        sessionMonitor.sessionsByProminence
    }

    private var shownSessions: [Session] {
        Array(rowSessions.prefix(Self.maxRows))
    }

    private var hiddenRowCount: Int {
        max(0, rowSessions.count - Self.maxRows)
    }

    /// Says what was folded when it is all stopped sessions, which it usually is.
    private var hiddenRowsLabel: String {
        let hidden = rowSessions.dropFirst(Self.maxRows)
        return hidden.allSatisfy { $0.phase == .stopped }
            ? "+\(hiddenRowCount) more done"
            : "+\(hiddenRowCount) more"
    }

    /// The card takes the colour of the session that most needs the user.
    private var borderColor: Color {
        sessionMonitor.activeSession?.phase.color ?? theme.textTertiary
    }
}
