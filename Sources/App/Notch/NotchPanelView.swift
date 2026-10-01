import SwiftUI
import Domain

/// The panel that hangs below the notch on hover: what is running, what is
/// nearly out, and what you can do about it.
struct NotchPanelView: View {
    let content: NotchContent
    var refresh: (() -> Void)?
    var snooze: (() -> Void)?

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !content.sessions.isEmpty {
                sessionList
            }

            if let prompt = blockedPrompt {
                permissionPrompt(prompt)
            }

            if !content.quotas.isEmpty {
                quotaCards
            }

            actions
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(.white)

            if let badge = headlineBadge {
                Text(badge.text)
                    .font(.system(size: 9.5, weight: .bold, design: theme.fontDesign))
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badge.color.opacity(0.18)))
                    .foregroundStyle(badge.color)
            }

            Spacer()

            if let summary = todaySummary {
                Text(summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    /// Named for what the panel is about right now: a session when one is
    /// running, otherwise the usage the notch exists to report.
    private var title: String {
        content.sessions.isEmpty ? "Usage" : "Claude Code"
    }

    private var headlineBadge: (text: String, color: Color)? {
        switch content.activity {
        case .awaitingInput: ("Needs you", .yellow)
        case .agentsWorking(let session): ("\(session.activeSubagentCount) agents", .blue)
        case .working: ("Active", .green)
        case .finished: ("Done", .green)
        case .quotaThreshold: ("Low quota", .orange)
        case .quotaGlance, nil: nil
        }
    }

    private var todaySummary: String? {
        guard let today = content.today else { return nil }
        return "Today · \(today.formattedWorkingTime) · \(today.formattedCost)"
    }

    private var blockedPrompt: String? {
        guard case .awaitingInput(let session) = content.activity else { return nil }
        return session.pendingPrompt
    }

    // MARK: - Sessions

    private var sessionList: some View {
        VStack(spacing: 1) {
            ForEach(content.sessions, id: \.id) { session in
                HStack(spacing: 10) {
                    Circle()
                        .fill(session.phase.color)
                        .frame(width: 7, height: 7)

                    Text(session.repoName)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer(minLength: 12)

                    Text(statusText(for: session))
                        .font(.system(size: 10.5, design: theme.fontDesign))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)

                    Text(session.durationDescription)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.38))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.04))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func statusText(for session: ClaudeSession) -> String {
        switch session.phase {
        case .awaitingInput:
            session.pendingPrompt ?? "Waiting for you"
        case .subagentsWorking:
            "\(session.activeSubagentCount) agents working"
        case .active:
            session.completedTaskCount > 0 ? "Active · \(session.completedTaskCount) tasks" : "Active"
        case .stopped:
            "Turn finished"
        case .ended:
            session.completedTaskCount > 0 ? "Ended · \(session.completedTaskCount) tasks" : "Ended"
        }
    }

    // MARK: - Permission prompt

    private func permissionPrompt(_ prompt: String) -> some View {
        Text(prompt)
            .font(.system(size: 11.5, design: theme.fontDesign))
            .foregroundStyle(.yellow.opacity(0.95))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(.yellow.opacity(0.1))
                    .strokeBorder(.yellow.opacity(0.3))
            )
    }

    // MARK: - Quotas

    private var quotaCards: some View {
        HStack(spacing: 9) {
            ForEach(Array(content.quotas.enumerated()), id: \.offset) { _, quota in
                quotaCard(quota)
            }
        }
    }

    private func quotaCard(_ quota: UsageQuota) -> some View {
        let status = QuotaStatus.from(percentRemaining: quota.percentRemaining)
        let color = theme.statusColor(for: status)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(quota.compactTitle ?? quota.quotaType.shortLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(quota.percentRemaining))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(.white.opacity(0.14))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: geometry.size.width * progress(quota))
                    }
            }
            .frame(height: 4)

            Text(quota.compactResetTime.map { "resets \($0)" } ?? " ")
                .font(.system(size: 9.5, design: theme.fontDesign))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(0.055))
                .strokeBorder(.white.opacity(0.07))
        )
    }

    private func progress(_ quota: UsageQuota) -> Double {
        max(0, min(1, quota.percentRemaining / 100))
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 7) {
            NotchActionButton(title: "Refresh quotas", isProminent: true) { refresh?() }
            NotchActionButton(title: "Snooze 30m") { snooze?() }
            Spacer()
        }
    }
}

private struct NotchActionButton: View {
    let title: String
    var isProminent: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isProminent ? Color(red: 0.90, green: 0.82, blue: 1.0) : .white.opacity(0.78))
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(fill)
                        .strokeBorder(stroke)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var fill: Color {
        let base = isProminent ? Color.purple.opacity(0.24) : Color.white.opacity(0.08)
        return isHovering ? base.opacity(0.9) : base
    }

    private var stroke: Color {
        isProminent ? .purple.opacity(0.45) : .white.opacity(0.1)
    }
}
