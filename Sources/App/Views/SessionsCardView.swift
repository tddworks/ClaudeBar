import SwiftUI
import Domain

/// The one Claude Code card in the menu popover.
///
/// A single session shows as `SessionIndicatorView`. Several sessions share
/// one card that stays small however many terminals are open: a strip with a
/// square per session and the count line (*1 needs you · 2 working · 5 done*),
/// then a row for each session still in play. Done sessions need nothing from
/// the person, so they wait behind ▾, folded by repo
/// (docs/features/session-hooks/design.md).
struct SessionsCardView: View {
    let sessionMonitor: SessionMonitor

    /// How many rows of sessions in play the closed card shows before "+N more".
    static let maxRows = 5
    /// How many squares the strip draws; the count line carries the rest.
    static let maxSquares = 12

    @Environment(\.appTheme) private var theme
    private var card = SessionsCardState.shared

    init(sessionMonitor: SessionMonitor) {
        self.sessionMonitor = sessionMonitor
    }

    var body: some View {
        // The durations read the clock, which no observable change drives;
        // ticking once a second keeps them moving while the popover is open.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if sessionMonitor.sessions.count == 1, let session = sessionMonitor.activeSession {
                SessionIndicatorView(session: session)
            } else {
                manySessions(now: context.date)
            }
        }
    }

    // MARK: - Several sessions

    private func manySessions(now: Date) -> some View {
        let inPlay = sessionMonitor.sessionsInPlay
        let tally = sessionMonitor.tally
        let shown = card.showsDone ? inPlay : Array(inPlay.prefix(Self.maxRows))
        let hidden = inPlay.count - shown.count

        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    strip
                    Text("Claude Code")
                        .popoverFont(11, weight: .bold, design: theme.fontDesign)
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 4)
                    toggle
                }
                countLine(tally, now: now)
            }

            if !shown.isEmpty || card.showsDone {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shown) { session in
                        sessionRow(session)
                    }
                    if hidden > 0 {
                        moreButton("+\(hidden) more")
                    } else if !shown.isEmpty, !card.showsDone, tally.done > 0 {
                        moreButton("\(tally.done) done ›")
                    }
                    if card.showsDone {
                        if !shown.isEmpty, tally.done > 0 {
                            Text("DONE")
                                .popoverFont(8, weight: .bold, design: theme.fontDesign)
                                .tracking(1)
                                .foregroundStyle(theme.textTertiary)
                                .padding(.top, 2)
                        }
                        ForEach(sessionMonitor.doneByRepo) { repo in
                            doneRow(repo, now: now)
                        }
                    }
                }
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

    /// A square per session in its phase colour, most pressing first.
    private var strip: some View {
        HStack(spacing: 3) {
            ForEach(sessionMonitor.sessionsByProminence.prefix(Self.maxSquares)) { session in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.color(for: session.phase))
                    .overlay(RoundedRectangle(cornerRadius: 1.5)
                        .stroke(theme.glassBorder, lineWidth: theme.isOutlined ? 1.5 : 0))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var toggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { card.showsDone.toggle() }
        } label: {
            Image(systemName: card.showsDone ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.cardGradient))
                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: max(1, theme.cardBorderWidth * 0.6)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.showsDone ? "Hide done sessions" : "Show done sessions")
    }

    /// *1 needs you · 2 working · 5 done*, a kind with none left out; when
    /// all are done, when the last one finished: *7 done · finished 2m ago*.
    private func countLine(_ tally: SessionTally, now: Date) -> some View {
        var parts: [Text] = []
        if tally.needsYou > 0 {
            parts.append(Text("\(tally.needsYou) needs you").foregroundStyle(theme.color(for: .awaitingInput)).bold())
        }
        if tally.working > 0 { parts.append(Text("\(tally.working) working")) }
        if tally.done > 0 {
            let allDone = tally.needsYou == 0 && tally.working == 0
            let last = sessionMonitor.doneByRepo.first.map { " · finished \(Self.ago($0.lastFinishedAt, now: now))" } ?? ""
            parts.append(Text("\(tally.done) done" + (allDone ? last : "")))
        }
        let line = parts.dropFirst().reduce(parts.first ?? Text("")) { Text("\($0) · \($1)") }
        return line
            .popoverFont(9, weight: .medium, design: theme.fontDesign)
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
    }

    private func sessionRow(_ session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            sessionLine(session)
            if let title = session.title {
                titleLine(title)
            }
        }
    }

    private func sessionLine(_ session: ClaudeSession) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.color(for: session.phase))
                .frame(width: 7, height: 7)

            Text(session.repoName)
                .popoverFont(10, weight: .semibold, design: theme.fontDesign)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)

            Text(session.phase.label.uppercased())
                .badge(theme.color(for: session.phase))

            Spacer()

            if session.completedTaskCount > 0 {
                Label("\(session.completedTaskCount)", systemImage: "checkmark.circle.fill")
                    .popoverFont(9, weight: .medium, design: theme.fontDesign)
                    .foregroundStyle(theme.textSecondary)
            }

            if session.activeSubagentCount > 0 {
                Label("\(session.activeSubagentCount)", systemImage: "person.2.fill")
                    .popoverFont(9, weight: .medium, design: theme.fontDesign)
                    .foregroundStyle(theme.textSecondary)
            }

            Text(session.durationDescription)
                .popoverFont(9, weight: .medium, design: theme.fontDesign)
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// One repo's Done sessions: *claudebar ×3 · just now*, with the
    /// session's title when the row stands for one.
    private func doneRow(_ repo: DoneRepo, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            doneLine(repo, now: now)
            if let title = repo.title {
                titleLine(title)
            }
        }
    }

    private func doneLine(_ repo: DoneRepo, now: Date) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.color(for: .stopped))
                .frame(width: 7, height: 7)

            Text(repo.repoName)
                .popoverFont(10, weight: .medium, design: theme.fontDesign)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)

            if repo.count > 1 {
                Text("×\(repo.count)")
                    .popoverFont(9, weight: .bold, design: theme.fontDesign)
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            Text(Self.ago(repo.lastFinishedAt, now: now))
                .popoverFont(9, weight: .medium, design: theme.fontDesign)
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// A session's title under its repo, lined up with the repo name past the dot.
    private func titleLine(_ title: String) -> some View {
        Text(title)
            .popoverFont(9, weight: .medium, design: theme.fontDesign)
            .foregroundStyle(theme.textTertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 15)
    }

    private func moreButton(_ title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { card.showsDone = true }
        } label: {
            Text(title)
                .popoverFont(9, weight: .medium, design: theme.fontDesign)
                .foregroundStyle(theme.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 15)
    }

    /// *just now*, *21m ago*, *2h 32m ago*.
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date))) / 60
        switch minutes {
        case 0: return "just now"
        case ..<60: return "\(minutes)m ago"
        default: return minutes % 60 == 0 ? "\(minutes / 60)h ago" : "\(minutes / 60)h \(minutes % 60)m ago"
        }
    }
}

/// Whether the Claude Code card shows its Done sessions. Kept while
/// ClaudeBar runs, so closing and reopening the popover leaves it as it was;
/// closed at launch, and never a setting.
@MainActor
@Observable
final class SessionsCardState {
    static let shared = SessionsCardState()
    var showsDone = false
}
