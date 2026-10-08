import SwiftUI
import Domain

/// *THE BOARD* — up to a hundred places in a list of fixed height that
/// scrolls inside the card, with the period and provider filters in its
/// header. Takes plain values, so it renders the same in the popover and in
/// a still image.
struct LeaderboardBoardCard: View {
    let top: [Standing]
    /// Your own standing in the view, when ranked.
    let mine: Standing?
    let myUsername: String?
    /// Your own row shows `@i•••` when your name is hidden in the popover.
    var hidesMyName = false
    let error: String?
    /// The board for this view hasn't come back yet: it says so, never that no one is on it.
    var isLoading = false
    @Binding var period: BoardPeriod
    @Binding var provider: String?
    /// The providers you share, with the names ClaudeBar shows for them.
    let sharedProviders: [(id: String, name: String)]

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    /// Whether the list shows your own row right now; `nil` until it says.
    @State private var isYourRowInView: Bool?

    /// Rows visible before the list scrolls; the card keeps this height.
    static let visibleRows = 7
    private static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 6
    /// Room round each row for its outline, inside the list's clip.
    private static let inset: CGFloat = 2

    private var leader: Int { max(top.first?.total ?? 0, 1) }

    var body: some View {
        LeaderboardCard {
            header
            providerFilter
            if top.isEmpty {
                Text(error ?? (isLoading ? "Loading the board…" : "No one is on the board for \(period.label.lowercased()) yet."))
                    .font(theme.font(size: 12))
                    .foregroundStyle(error == nil ? theme.textTertiary : theme.statusCritical)
            } else {
                standingsList
            }
        }
    }

    // MARK: Header and filters

    private var title: String {
        top.count >= 100 ? "TOP 100" : top.count > 1 ? "THE BOARD · \(top.count) MEMBERS" : "THE BOARD"
    }

    /// The label and the period switch side by side when they fit; the
    /// switch under the label when they don't, never wider than the card.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center) {
                label.fixedSize()
                Spacer(minLength: 8)
                periodPicker
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                periodPicker
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(theme.font(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
    }

    private var periodPicker: some View {
        InkSegmentedPicker(title: "Period", options: BoardPeriod.allCases, selection: $period, label: \.label)
            .fixedSize()
    }

    /// Small text chips inside the card, so they read as a filter on it
    /// rather than as more tabs; shown when more than one provider is shared.
    @ViewBuilder
    private var providerFilter: some View {
        if sharedProviders.count > 1 {
            HStack(spacing: 4) {
                FilterChip(title: "All", isOn: provider == nil) { provider = nil }
                ForEach(sharedProviders, id: \.id) { shared in
                    FilterChip(title: shared.name, isOn: provider == shared.id) { provider = shared.id }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: The list

    /// While the list doesn't show your row, a pinned row of yours sits under
    /// it and scrolls it to you.
    private var standingsList: some View {
        let scrolls = top.count > Self.visibleRows
        let height = CGFloat(min(top.count, Self.visibleRows)) * (Self.rowHeight + Self.rowSpacing) - Self.rowSpacing
            + Self.inset * 2 + (scrolls ? Self.rowHeight / 2 : 0)
        return ScrollViewReader { proxy in
            VStack(spacing: Self.rowSpacing) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(top) { standing in
                            let isMe = standing.username == myUsername
                            row(standing, isMe: isMe)
                                .id(standing.rank)
                                .onScrollVisibilityChange(threshold: 0.6) { if isMe { isYourRowInView = $0 } }
                        }
                        // Ranked but outside the hundred shown.
                        if let mine, !top.contains(where: { $0.rank == mine.rank }) {
                            Text("· · ·").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.textTertiary)
                            row(mine, isMe: true).id(mine.rank)
                                .onScrollVisibilityChange(threshold: 0.6) { isYourRowInView = $0 }
                        }
                    }
                    .padding(Self.inset)
                }
                .scrollDisabled(!scrolls)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .mask {
                    // A soft bottom edge says there is more below.
                    VStack(spacing: 0) {
                        Rectangle()
                        if scrolls {
                            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 18)
                        }
                    }
                }

                if let mine, PinnedPlace.shows(isRanked: true, listScrolls: scrolls,
                                               isYourRowInView: isYourRowInView ?? (mine.rank <= Self.visibleRows)) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(mine.rank, anchor: .center) }
                    } label: {
                        row(mine, isMe: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Self.inset)
                    .help("Scroll to your place")
                }
            }
        }
    }

    /// One line per place; its bar is the row's own background, filled in
    /// proportion to the leader and split by provider in each provider's own
    /// colour, so a row says how much and what.
    private func row(_ standing: Standing, isMe: Bool) -> some View {
        let fraction = min(1, max(0, Double(standing.total) / Double(leader)))
        let shape = RoundedRectangle(cornerRadius: 8)
        return HStack(spacing: 8) {
            OutlinedNumber(text: "\(standing.rank)", size: 15, color: standing.rank <= 3 ? theme.statusWarning : nil)
                .frame(width: 22)
            Text(isMe ? leaderboardName(standing.username, hidden: hidesMyName) : "@" + standing.username)
                .font(theme.font(size: 12, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let link = standing.link {
                ProfileLinkIcon(link: link, username: standing.username)
            }
            if isMe {
                Text("YOU")
                    .font(theme.font(size: 9, weight: .heavy))
                    .foregroundStyle(theme.textOnStatus)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.accentPrimary))
                    .fixedSize()
            }
            Spacer(minLength: 6)
            Text(LeaderboardStandingsView.tokens(standing.total))
                .font(theme.font(size: 12, weight: .heavy))
                .foregroundStyle(theme.textPrimary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
        .background(alignment: .leading) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    shape.fill(theme.progressTrack.opacity(0.5))
                    HStack(spacing: 0) {
                        ForEach(mix(of: standing), id: \.provider) { part in
                            Rectangle()
                                .fill(ProviderVisualIdentityLookup.color(for: part.provider, scheme: colorScheme).opacity(0.38))
                                .frame(width: geo.size.width * fraction * part.share)
                        }
                    }
                }
                .clipShape(shape)
            }
        }
        .overlay(shape.stroke(isMe ? theme.accentPrimary : theme.glassBorder.opacity(theme.isOutlined ? 0.9 : 0.4),
                              lineWidth: isMe ? max(1.5, theme.cardBorderWidth * 0.8) : max(1, theme.cardBorderWidth * 0.6)))
        .accessibilityElement(children: .combine)
    }

    /// Each provider's share of a standing, largest first.
    private func mix(of standing: Standing) -> [(provider: String, share: Double)] {
        let total = max(1, standing.byProvider.values.reduce(0, +))
        return standing.byProvider.sorted { $0.value > $1.value }.map { ($0.key, Double($0.value) / Double(total)) }
    }
}

/// A small text chip that filters a card's content, in the period picker's
/// colours: ink when on, outlined when off — deliberately unlike the
/// navigation pills.
struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.font(size: 9.5, weight: .heavy))
                // The period picker's colours: ink fill, card-paper label — legible in every theme.
                .foregroundStyle(isOn ? theme.cardGradient : LinearGradient(colors: [theme.textSecondary], startPoint: .leading, endPoint: .trailing))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isOn ? theme.glassBorder : Color.clear)
                        .overlay(Capsule().stroke(isOn ? Color.clear : theme.glassBorder.opacity(0.35), lineWidth: 1))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// *Your place* under the board: a row of yours pinned below the list, so
/// you find yourself without scrolling — only while the list doesn't show
/// your own row, or you'd see yourself twice.
enum PinnedPlace {
    static func shows(isRanked: Bool, listScrolls: Bool, isYourRowInView: Bool) -> Bool {
        isRanked && listScrolls && !isYourRowInView
    }
}
