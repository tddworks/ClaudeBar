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
    @State private var preview: [DailyTokens] = []

    private var username: Username? { Username(name) }

    /// The body of `PUT /usage` for today, as the client encodes it.
    private var payload: String {
        let today = DailyTokens.day(of: Date())
        let rows = preview.map { day in
            "    {\"provider\": \"\(day.provider)\", \"day\": \"\(day.day)\",\n     \"input\": \(day.input), \"output\": \(day.output), \"cacheWrite\": \(day.cacheWrite),\n     \"cacheRead\": \(day.cacheRead), \"unsplit\": \(day.unsplit)}"
        }
        return "PUT /usage\n{\n  \"today\": \"\(today)\",\n  \"days\": [\n\(rows.isEmpty ? "    (no tokens today yet)" : rows.joined(separator: ",\n"))\n  ]\n}"
    }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shareable, id: \.self) { id in
                            ProviderPill(providerId: id, providerName: leaderboardProviderName(id, in: monitor),
                                         isSelected: sharing.contains(id), hasData: true) {
                                if sharing.contains(id) { sharing.remove(id) } else { sharing.insert(id) }
                            }
                            .accessibilityAddTraits(sharing.contains(id) ? .isSelected : [])
                        }
                    }
                    .padding(4)
                }

                DisclosureGroup("Exactly what gets uploaded", isExpanded: $showPayload) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signed as @\(username?.value ?? "you"), hourly. This is today; the first upload sends each of the last 30 days the same way. Nothing else leaves this Mac.")
                            .font(.system(size: 11, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(payload)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(theme.glassBorder, style: StrokeStyle(lineWidth: max(1, theme.cardBorderWidth * 0.7), dash: [5, 4]))
                            )
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)
                .task(id: showPayload ? sharing : []) {
                    if showPayload { preview = await leaderboard.preview(sharing: sharing) }
                }

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

extension BoardPeriod: Identifiable {
    public var id: String { rawValue }
}

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
            rankCard
            boardCard
            footer
        }
        .task(id: view) { await load() }
        .task(id: membership.lastUpload) { await load() }
    }

    // MARK: Your rank

    private var rankCard: some View {
        LeaderboardCard {
            HStack(alignment: .firstTextBaseline) {
                CardLabel(text: (["YOUR RANK", period.label] + [provider.map { leaderboardProviderName($0, in: monitor) }].compactMap { $0 })
                    .joined(separator: " · ").uppercased())
                Spacer()
                if mine?.visible == false {
                    Label("Hidden", systemImage: "eye.slash")
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                OutlinedNumber(text: mine?.standing.map { "#\($0.rank)" } ?? "–", size: 42, color: theme.accentPrimary)
                    .accessibilityLabel(mine?.standing.map { "Rank \($0.rank)" } ?? "Not ranked yet")
                VStack(alignment: .leading, spacing: 3) {
                    Text(membership.username?.description ?? "")
                        .font(.system(size: 15, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text("\(Self.tokens(mine?.standing?.total ?? 0)) tokens")
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                    if let gap = gapLine {
                        Text(gap)
                            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Spacer(minLength: 8)
                if let standing = mine?.standing, !standing.byProvider.isEmpty {
                    YourMix(byProvider: standing.byProvider, monitor: monitor)
                        .frame(width: 112)
                }
            }
        }
    }

    /// How far to the place above, or how far ahead of the one below.
    private var gapLine: String? {
        guard let me = mine?.standing else { return nil }
        if me.rank > 1, let above = top.first(where: { $0.rank == me.rank - 1 }) {
            return "\(Self.tokens(above.total - me.total)) behind #\(above.rank)"
        }
        if me.rank == 1, let next = top.first(where: { $0.rank == 2 }) {
            return "\(Self.tokens(me.total - next.total)) ahead of #2"
        }
        return me.rank == 1 ? "Top of the board" : nil
    }

    // MARK: The board

    private var boardCard: some View {
        LeaderboardBoardCard(
            top: top, mine: mine?.standing, myUsername: membership.username?.value, error: error,
            period: $period, provider: $provider,
            sharedProviders: membership.sharing.sorted().map { ($0, leaderboardProviderName($0, in: monitor)) })
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: leaderboard.uploader.lastError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(status)
                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                .lineLimit(2)
            Spacer(minLength: 8)
            Link(destination: leaderboard.boardPage) {
                Label("Full board", systemImage: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.glassBackground))
                    .overlay(Capsule().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(leaderboard.uploader.lastError == nil ? theme.textTertiary : theme.statusWarning)
        .padding(.horizontal, 4)
    }

    private var status: String {
        if let error = leaderboard.uploader.lastError { return "Upload failed: \(error.errorDescription ?? "")" }
        if leaderboard.uploader.isUploading { return "Uploading…" }
        guard let last = membership.lastUpload else { return "Waiting for the first upload" }
        return "Uploaded \(last.formatted(.relative(presentation: .named))) · hourly"
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

/// *YOUR MIX* — what your tokens were spent on: a stacked bar in each
/// provider's own colour, and the three largest shares.
private struct YourMix: View {
    let byProvider: [String: Int]
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var parts: [(id: String, share: Double)] {
        let total = Double(max(1, byProvider.values.reduce(0, +)))
        return byProvider.sorted { $0.value > $1.value }.map { ($0.key, Double($0.value) / total) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("YOUR MIX")
                .font(.system(size: 9, weight: .bold, design: theme.fontDesign))
                .tracking(1)
                .foregroundStyle(theme.textTertiary)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(parts, id: \.id) { part in
                        Rectangle()
                            .fill(color(part.id))
                            .frame(width: geo.size.width * part.share)
                    }
                }
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: max(1, theme.cardBorderWidth * 0.6)))
            }
            .frame(height: 8)
            ForEach(parts.prefix(3), id: \.id) { part in
                HStack(spacing: 5) {
                    Circle().fill(color(part.id)).frame(width: 6, height: 6)
                    Text(leaderboardProviderName(part.id, in: monitor))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(Int((part.share * 100).rounded()))%")
                        .fixedSize()
                }
                .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ id: String) -> Color {
        ProviderVisualIdentityLookup.color(for: id, scheme: colorScheme)
    }
}
