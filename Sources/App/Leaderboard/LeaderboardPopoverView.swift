import SwiftUI
import Domain

/// The popover's *LEADERBOARD* tab: join with a username, or see your rank.
struct LeaderboardPopoverView: View {
    let leaderboard: Leaderboard
    let monitor: QuotaMonitor

    var body: some View {
        if leaderboard.membership.isJoined {
            LeaderboardStandingsView(leaderboard: leaderboard, monitor: monitor)
        } else {
            LeaderboardJoinView(leaderboard: leaderboard, monitor: monitor)
        }
    }
}

/// A provider's name as ClaudeBar shows it, from its id.
@MainActor
func leaderboardProviderName(_ id: String, in monitor: QuotaMonitor) -> String {
    monitor.allProviders.compactMap { $0 as? Account }.first { $0.provider.id == id }?.provider.name ?? id.capitalized
}

/// A card in the current theme.
struct LeaderboardCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)
                    .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
    }
}

private struct CardLabel: View {
    let text: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
            .tracking(1)
            .foregroundStyle(theme.textSecondary)
    }
}

// MARK: - Join

struct LeaderboardJoinView: View {
    let leaderboard: Leaderboard
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var name = ""
    @State private var sharing: Set<String> = []
    @State private var error: String?
    @State private var isJoining = false
    @State private var showPayload = false

    private var username: Username? { Username(name) }
    private var shareable: [String] { leaderboard.membership.shareableProviders.sorted() }

    private var hint: (text: String, color: Color) {
        if name.isEmpty { return ("3–20 letters, numbers, - or _. Shown publicly.", theme.textTertiary) }
        if username == nil { return ("Use 3–20 letters, numbers, - or _.", theme.statusCritical) }
        return ("Shown publicly as @\(name)", theme.statusHealthy)
    }

    var body: some View {
        VStack(spacing: 12) {
            LeaderboardCard {
                CardLabel(text: "JOIN THE BOARD")
                Text("Rank your token usage against other ClaudeBar users")
                    .font(.system(size: 15, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LeaderboardCard {
                CardLabel(text: "USERNAME")
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(theme.textTertiary)
                    TextField("", text: $name, prompt: Text("pick-a-name").foregroundStyle(theme.textTertiary))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Username")
                }
                .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.glassBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)))
                Text(hint.text)
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(hint.color)

                CardLabel(text: "SHARE TOKENS FROM").padding(.top, 4)
                if shareable.isEmpty {
                    Text("No provider on this Mac keeps token logs yet. Claude, Codex and Mistral do.")
                        .font(.system(size: 11, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
                ForEach(shareable, id: \.self) { id in
                    Toggle(isOn: Binding(
                        get: { sharing.contains(id) },
                        set: { on in if on { sharing.insert(id) } else { sharing.remove(id) } }
                    )) {
                        Text(leaderboardProviderName(id, in: monitor))
                            .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .toggleStyle(.checkbox)
                }

                DisclosureGroup("Exactly what gets uploaded", isExpanded: $showPayload) {
                    Text("Your username, and for each ticked provider and day: input, output, cache-write and cache-read token counts. Never prompts, file names, projects, costs or your account email. Leaving deletes everything on the server.")
                        .font(.system(size: 11, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

                if let error {
                    Text(error)
                        .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.statusCritical)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await join() }
                } label: {
                    Text(isJoining ? "Joining…" : sharing.isEmpty ? "Pick at least one provider" : "Join leaderboard")
                        .font(.system(size: 13, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textOnStatus)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: theme.pillCornerRadius).fill(theme.accentGradient))
                }
                .buttonStyle(.plain)
                .disabled(username == nil || sharing.isEmpty || isJoining)
                .opacity(username == nil || sharing.isEmpty ? 0.5 : 1)
            }
        }
        .onAppear {
            if sharing.isEmpty { sharing = Set(shareable) }
        }
    }

    private func join() async {
        guard let username else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            try await leaderboard.join(as: username, sharing: sharing)
            error = nil
        } catch {
            self.error = (error as? LeaderboardError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Standings

struct LeaderboardStandingsView: View {
    let leaderboard: Leaderboard
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var period: BoardPeriod = .sevenDays
    @State private var provider: String?
    @State private var mine: MemberSummary?
    @State private var top: [Standing] = []
    @State private var error: String?

    private var view: BoardView { BoardView(period: period, provider: provider) }
    private var membership: LeaderboardMembership { leaderboard.membership }

    var body: some View {
        VStack(spacing: 12) {
            LeaderboardCard {
                HStack(alignment: .center, spacing: 14) {
                    Text(mine?.standing.map { "#\($0.rank)" } ?? "–")
                        .font(.system(size: 44, weight: .heavy, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .accessibilityLabel(mine?.standing.map { "Rank \($0.rank)" } ?? "Not ranked yet")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(membership.username?.description ?? "")
                            .font(.system(size: 15, weight: .bold, design: theme.fontDesign))
                            .foregroundStyle(theme.textPrimary)
                        Text("\(Self.tokens(mine?.standing?.total ?? 0)) tokens · \(period.label.lowercased())")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                        if mine?.visible == false {
                            Text("Hidden from the web board")
                                .font(.system(size: 11, design: theme.fontDesign))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }

                Picker("Period", selection: $period) {
                    ForEach(BoardPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Provider", selection: $provider) {
                    Text("All providers").tag(String?.none)
                    ForEach(membership.sharing.sorted(), id: \.self) { id in
                        Text(leaderboardProviderName(id, in: monitor)).tag(Optional(id))
                    }
                }
                .labelsHidden()
            }

            LeaderboardCard {
                CardLabel(text: "TOP OF THE BOARD")
                if top.isEmpty {
                    Text(error ?? "No one is on the board for \(period.label.lowercased()) yet.")
                        .font(.system(size: 12, design: theme.fontDesign))
                        .foregroundStyle(error == nil ? theme.textTertiary : theme.statusCritical)
                }
                ForEach(top.prefix(5)) { standing in
                    row(standing, isMe: standing.username == membership.username?.value)
                }
                if let me = mine?.standing, me.rank > 5 {
                    Text("· · ·").font(.system(size: 11)).foregroundStyle(theme.textTertiary).frame(maxWidth: .infinity)
                    row(me, isMe: true)
                }
            }

            HStack {
                Text(footer)
                    .font(.system(size: 11, design: theme.fontDesign))
                    .foregroundStyle(leaderboard.uploader.lastError == nil ? theme.textTertiary : theme.statusWarning)
                    .lineLimit(2)
                Spacer()
                Link("Full board", destination: leaderboard.boardPage)
                    .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
            }
        }
        .task(id: view) { await load() }
        .task(id: membership.lastUpload) { await load() }
    }

    private var footer: String {
        if let error = leaderboard.uploader.lastError { return "Upload failed: \(error.errorDescription ?? "")" }
        guard let last = membership.lastUpload else { return "Uploading…" }
        return "Uploaded \(last.formatted(.relative(presentation: .named))) · hourly"
    }

    private func row(_ standing: Standing, isMe: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(standing.rank)")
                .font(.system(size: 12, weight: .heavy, design: theme.fontDesign))
                .frame(width: 26)
            Text("@" + standing.username + (isMe ? " (you)" : ""))
                .font(.system(size: 12, weight: .bold, design: theme.fontDesign))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(Self.tokens(standing.total))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(theme.textPrimary)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isMe ? theme.statusHealthy.opacity(0.25) : theme.glassBackground))
    }

    private func load() async {
        do {
            async let board = leaderboard.board(in: view)
            async let me = membership.myStanding(in: view)
            (top, mine) = try await (board, me)
            error = nil
        } catch {
            self.error = (error as? LeaderboardError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000_000...: String(format: "%.2fB", Double(count) / 1e9)
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1e6)
        case 1_000...: String(format: "%.1fK", Double(count) / 1e3)
        default: "\(count)"
        }
    }
}
