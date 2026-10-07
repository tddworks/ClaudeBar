import Kit
import SwiftUI

// MARK: - Score Line

/// A `.scoreLine` header's top row: PLAYER and its status, coins, WORLD and
/// TIME, in the theme's display face — light on the sky, with an ink shadow.
struct ScoreLineView: View {
    let line: ScoreLine

    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        HStack(alignment: .top) {
            slot(line.player, line.status)
            Spacer(minLength: 6)
            slot("COINS", "×\(line.coins)", coin: true)
            Spacer(minLength: 6)
            slot("WORLD", line.world)
            Spacer(minLength: 6)
            slot("TIME", line.time)
        }
        .accessibilityElement(children: .combine)
    }

    private func slot(_ label: String, _ value: String, coin: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(theme.displayFont(size: 12))
                .lineLimit(1)
            HStack(spacing: 3) {
                if coin { PixelCoin(color: theme.statusWarning, edge: theme.glassBorder).frame(width: 7, height: 9) }
                Text(value)
                    .font(theme.displayFont(size: 15))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(theme.glassBackground)
        .shadow(color: theme.glassBorder, radius: 0, x: 1.5, y: 1.5)
    }
}

/// A coin in art pixels: an inked oval with a slot down its middle.
struct PixelCoin: View {
    let color: Color
    let edge: Color

    var body: some View {

        let _ = KitObservation.track()
        Canvas { context, size in
            let unit = min(size.width / 5, size.height / 7)
            func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                context.fill(Path(CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)), with: .color(c))
            }
            fill(1, 0, 3, 7, edge); fill(0, 1, 5, 5, edge)
            fill(1, 1, 3, 5, color); fill(2, 2, 1, 3, edge.opacity(0.45))
        }
    }
}

/// A "?" in art pixels: 4 wide, 7 tall.
struct QuestionMark: View {
    let color: Color

    var body: some View {

        let _ = KitObservation.track()
        Canvas { context, size in
            let unit = min(size.width / 4, size.height / 7)
            for (x, y, w, h) in [(0, 0, 4, 1), (3, 1, 1, 2), (0, 1, 1, 1), (1, 3, 2, 1), (1, 4, 1, 1), (1, 6, 1, 1)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
                context.fill(Path(CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit)), with: .color(color))
            }
        }
    }
}

// MARK: - ? Block

/// The refresh button of a `.scoreLine` header: a ? block. Hit it and it
/// bumps up and a coin pops out; while a refresh runs, it keeps bobbing.
struct QuestionBlockButton: View {
    let isSyncing: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var bump = false
    @State private var coin = false
    @State private var bob = false

    var body: some View {

        let _ = KitObservation.track()
        Button {
            withAnimation(.easeOut(duration: 0.12)) { bump = true; coin = true }
            withAnimation(.easeIn(duration: 0.14).delay(0.12)) { bump = false }
            withAnimation(.easeOut(duration: 0.3).delay(0.35)) { coin = false }
            action()
        } label: {
            ZStack {
                PixelCoin(color: theme.statusWarning, edge: theme.glassBorder)
                    .frame(width: 12, height: 17)
                    .offset(y: coin ? -30 : 0)
                    .opacity(coin ? 1 : 0)

                block
                    .offset(y: bump ? -7 : (bob ? -3 : 0))
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .onChange(of: isSyncing, initial: true) { _, syncing in
            withAnimation(syncing ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true) : .default) {
                bob = syncing
            }
        }
        .accessibilityLabel(isSyncing ? "Syncing" : "Refresh")
    }

    private var block: some View {
        ZStack {
            // The hard shadow is the outline's alone: on the whole block it
            // would double the ? and the rivets.
            Rectangle().fill(theme.glassBorder).themeShadow(theme, scale: 0.5)
            Rectangle().fill(theme.accentPrimary).padding(3)
            // The top's shine and the four rivets.
            VStack { Rectangle().fill(.white.opacity(0.45)).frame(height: 3); Spacer() }.padding(3)
            ForEach(0..<4, id: \.self) { corner in
                Rectangle().fill(theme.glassBorder)
                    .frame(width: 3, height: 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing][corner])
                    .padding(6)
            }
            QuestionMark(color: theme.glassBorder.opacity(0.7))
                .frame(width: 12, height: 21)
        }
        .frame(width: 34, height: 34)
    }
}
