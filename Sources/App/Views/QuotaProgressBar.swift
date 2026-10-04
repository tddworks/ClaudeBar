import SwiftUI
import Domain

// MARK: - Progress Bar

/// A quota's or a budget's bar. Glass themes draw a thin flat track; an
/// outlined theme (Pop) a tall inked capsule over a striped track, its fill
/// ending in an ink edge.
struct QuotaProgressBar<Fill: ShapeStyle>: View {
    /// 0–100; clamped.
    let percent: Double
    let fill: Fill
    var animate: Bool = true
    var delay: Double = 0

    @Environment(\.appTheme) private var theme

    private var fraction: Double { max(0, min(100, percent)) / 100 }

    var body: some View {
        if theme.isOutlined { outlined } else { glass }
    }

    private var glass: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.progressTrack)
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
                    .frame(width: animate ? geo.size.width * fraction : 0)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animate)
            }
        }
        .frame(height: 5)
    }

    private var outlined: some View {
        let edge = theme.cardBorderWidth * 0.8
        return GeometryReader { geo in
            let width = animate ? geo.size.width * fraction : 0
            ZStack(alignment: .leading) {
                StripedTrack(base: theme.progressTrack, stripe: theme.glassBorder.opacity(0.07))
                Rectangle()
                    .fill(fill)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(theme.glassBorder).frame(width: fraction > 0 && fraction < 1 ? edge : 0)
                    }
                    .frame(width: width)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(delay + 0.2), value: animate)
            }
            .clipShape(Capsule())
            .overlay(Capsule().stroke(theme.glassBorder, lineWidth: edge))
        }
        .frame(height: 12)
    }
}

/// Diagonal stripes, the paper under an outlined theme's bar.
private struct StripedTrack: View {
    let base: Color
    let stripe: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(stripe), lineWidth: 2)
                x += 6
            }
        }
    }
}

// MARK: - Outlined Number

/// A big number printed the outlined way: white, inked round its edge,
/// with a hard ink shadow. Glass themes print it plainly.
struct OutlinedNumber: View {
    let text: String
    let size: CGFloat
    var color: Color? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.isOutlined {
            let stroke: CGFloat = size >= 24 ? 1.5 : 1
            let face = Text(text).font(theme.displayFont(size: size))
            ZStack {
                ForEach(Self.directions.indices, id: \.self) { i in
                    face.foregroundStyle(theme.glassBorder)
                        .offset(x: Self.directions[i].0 * stroke, y: Self.directions[i].1 * stroke)
                }
                face.foregroundStyle(color ?? .white)
            }
            .background(face.foregroundStyle(theme.glassBorder).offset(x: stroke + 1.5, y: stroke + 1.5))
        } else {
            Text(text)
                .font(theme.displayFont(size: size))
                .foregroundStyle(color ?? theme.textPrimary)
        }
    }

    private static let directions: [(CGFloat, CGFloat)] = [
        (-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1),
    ]
}

// MARK: - Pace Badge

/// How a quota is pacing against its window, as an outlined theme's dashed
/// sticker: on track, running hot, room to spare — or, compact, the pace's
/// icon alone.
struct PaceBadge: View {
    let pace: UsagePace
    var compact: Bool = false

    @Environment(\.appTheme) private var theme

    private var color: Color {
        switch pace {
        case .ahead: PopTheme.coralSoft
        case .behind: PopTheme.mintSoft
        case .onPace, .unknown: PopTheme.sky
        }
    }

    var body: some View {
        Group {
            if compact {
                Image(systemName: pace.symbolName)
            } else {
                Text(pace.displayName.uppercased())
            }
        }
        .font(.system(size: 7.5, weight: .heavy, design: theme.fontDesign))
        .foregroundStyle(theme.textPrimary)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(RoundedRectangle(cornerRadius: 5).fill(color))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(theme.glassBorder, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 1.5]))
        )
        .fixedSize()
        .help(pace.displayName)
    }
}
