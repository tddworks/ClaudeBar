import SwiftUI
import Domain

/// The shared image of a `RankCard`, in the theme the member wears: a card
/// of that theme on its background, the way the popover draws one.
/// Design: design-concept/leaderboard/share-standing.html.
struct RankCardImage: View {
    let card: RankCard
    let shape: RankCard.Shape
    /// `@itshan`, or `@i•••` when the member masks it.
    let name: String
    let providerName: (String) -> String
    /// Passed in, not read from the environment: `ImageRenderer` renders
    /// outside the popover's window and inherits neither.
    let theme: any AppThemeProvider
    let colorScheme: ColorScheme

    /// Drawn at a third of its pixels; rendered at 3×.
    static let scale: CGFloat = 3
    static func points(_ shape: RankCard.Shape) -> CGSize {
        CGSize(width: shape.pixels.width / scale, height: shape.pixels.height / scale)
    }

    var body: some View {
        Group {
            switch shape {
            case .square: square
            case .wide: wide
            }
        }
        .foregroundStyle(theme.textPrimary)
        .padding(shape == .square ? 18 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(theme.cardGradient)
                .overlay(RoundedRectangle(cornerRadius: cardRadius).strokeBorder(theme.glassBorder, lineWidth: border))
        )
        .padding(12)
        .frame(width: Self.points(shape).width, height: Self.points(shape).height)
        .background(theme.backgroundGradient)
        .environment(\.appTheme, theme)
        .environment(\.colorScheme, colorScheme)
    }

    private var square: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { brand; Spacer(minLength: 6); viewPill }
            HStack(alignment: .bottom, spacing: 12) {
                rankNumber(size: 88)
                VStack(alignment: .leading, spacing: 4) {
                    if let members = membersLine { Text(members).font(theme.font(size: 13, weight: .bold)) }
                    placementBadge
                }
                .padding(.bottom, 10)
            }
            .padding(.top, 14)
            nameAndTokens.padding(.top, 6)
            mixBar.padding(.top, 12)
            Spacer(minLength: 8)
            footer
        }
    }

    private var wide: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                brand
                Spacer(minLength: 4)
                rankNumber(size: 96)
                Spacer(minLength: 4)
                if let members = membersLine { Text(members).font(theme.font(size: 13, weight: .bold)) }
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                HStack { Spacer(); viewPill }
                nameAndTokens.padding(.top, 10)
                placementBadge.padding(.top, 8)
                mixBar.padding(.top, 10)
                Spacer(minLength: 6)
                Text(Self.boardAddress).font(theme.font(size: 10, weight: .bold)).foregroundStyle(theme.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: Pieces

    /// The theme's card corners and border, never thinner than a hairline that survives 3×.
    private var cardRadius: CGFloat { min(26, theme.cardCornerRadius + 6) }
    private var border: CGFloat { max(1.5, theme.cardBorderWidth) }

    private var brand: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 22, height: 22)
            Text("ClaudeBar Leaderboard").font(theme.font(size: 13, weight: .heavy)).lineLimit(1).fixedSize()
        }
    }

    private var viewPill: some View {
        Text(Self.boardLabel(period: card.period, provider: card.provider, providerName: providerName))
            .font(theme.font(size: 10, weight: .heavy))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(theme.glassBackground))
            .overlay(Capsule().strokeBorder(theme.glassBorder, lineWidth: max(1, border * 0.7)))
    }

    private func rankNumber(size: CGFloat) -> some View {
        OutlinedNumber(text: "#\(card.rank)", size: size, color: theme.accentPrimary)
            .lineLimit(1).fixedSize()
    }

    private var nameAndTokens: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(theme.font(size: 24, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LeaderboardStandingsView.tokens(card.total)).font(theme.font(size: 20, weight: .heavy))
                Text("tokens").font(theme.font(size: 12, weight: .bold)).foregroundStyle(theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var placementBadge: some View {
        if let text = placementText {
            Text(text)
                .font(theme.font(size: 12, weight: .heavy))
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: theme.badgeCornerRadius ?? 6).fill(theme.accentGradient))
                .overlay(RoundedRectangle(cornerRadius: theme.badgeCornerRadius ?? 6).strokeBorder(theme.glassBorder, lineWidth: max(1, border * 0.7)))
                .foregroundStyle(theme.textOnAccent)
        }
    }

    private var mixBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(card.mix, id: \.provider) { part in
                        Rectangle().fill(color(part.provider)).frame(width: geo.size.width * CGFloat(part.percent) / 100)
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(Capsule())
                .background(Capsule().fill(theme.progressTrack))
                .overlay(Capsule().strokeBorder(theme.glassBorder, lineWidth: max(1, border * 0.7)))
            }
            .frame(height: 14)
            HStack(spacing: 12) {
                ForEach(card.mix.prefix(3), id: \.provider) { part in
                    HStack(spacing: 4) {
                        Circle().fill(color(part.provider)).frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(theme.glassBorder, lineWidth: 1))
                        Text("\(providerName(part.provider)) \(part.percent)%").lineLimit(1)
                    }
                }
            }
            .font(theme.font(size: 11, weight: .bold))
        }
    }

    private var footer: some View {
        HStack {
            Text(Self.boardAddress).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            Text("tokens only")
        }
        .font(theme.font(size: 10, weight: .bold))
        .foregroundStyle(theme.textTertiary)
    }

    // MARK: Words

    static let boardAddress = "claudebar.tddworks.com/leaderboard"

    /// *7 days · All providers*, *30 days · Codex*.
    static func boardLabel(period: BoardPeriod, provider: String?, providerName: (String) -> String) -> String {
        "\(period.label) · \(provider.map(providerName) ?? "All providers")"
    }

    private var membersLine: String? {
        card.members.map { "of \($0) members" }
    }

    private var placementText: String? {
        switch card.placement {
        case .top(let percent): "Top \(percent)%"
        case .rank(let members): "#\(card.rank) of \(members)"
        case .topHundred: "Top 100"
        case .none: nil
        }
    }

    private func color(_ provider: String) -> Color {
        ProviderVisualIdentityLookup.color(for: provider, scheme: colorScheme)
    }
}

extension RankCardImage {
    /// The image as a PNG at its shape's full pixels, for copying, saving and sharing.
    @MainActor
    func png() -> Data? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = Self.scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
