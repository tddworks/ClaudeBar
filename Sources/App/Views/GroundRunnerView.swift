import SwiftUI
import Domain

/// A theme's runner in its lane above the floor, drawn while the popover is
/// open. It takes no clicks; the action bar above it keeps them.
/// Design: docs/features/themes/design.md#the-runner.
struct GroundRunnerView: View {
    let runner: GroundRunner
    let status: QuotaStatus
    let isSyncing: Bool
    let floorHeight: CGFloat

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: RunnerLevel
    @State private var isShown = false

    /// Room over the lane for the coin to pop into.
    private static let headroom: CGFloat = 40

    init(runner: GroundRunner, status: QuotaStatus, isSyncing: Bool, floorHeight: CGFloat) {
        self.runner = runner
        self.status = status
        self.isSyncing = isSyncing
        self.floorHeight = floorHeight
        _level = State(initialValue: RunnerLevel(spriteWidth: runner.width))
    }

    var body: some View {
        TimelineView(.animation(paused: !isShown)) { timeline in
            Canvas { context, size in
                level.advance(to: timeline.date, pace: runner.pace(for: status), width: size.width, reduceMotion: reduceMotion)
                draw(in: &context, size: size, now: timeline.date)
            }
        }
        .frame(height: Self.headroom + runner.laneHeight + floorHeight)
        .onAppear { isShown = true }
        .onDisappear { isShown = false }
        .onChange(of: isSyncing) { wasSyncing, syncing in
            if wasSyncing, !syncing { level.celebrate(at: Date(), reduceMotion: reduceMotion) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let sprite = runner.sprite, px = runner.pixel
        let ground = size.height - floorHeight
        let top = ground - CGFloat(sprite.rows) * px - level.lift

        if let pit = level.pit {
            context.fill(Path(CGRect(x: pit, y: ground, width: RunnerLevel.pitWidth, height: floorHeight)), with: .color(theme.glassBorder))
        }

        if level.isGameOver {
            drawGameOver(in: &context, at: CGPoint(x: size.width / 2, y: ground - runner.laneHeight / 2))
            return
        }

        var figure = context
        if level.pit != nil {
            // Falling: seen in the lane and down the pit, behind the bricks.
            var visible = Path(CGRect(x: 0, y: 0, width: size.width, height: ground))
            if let pit = level.pit { visible.addRect(CGRect(x: pit, y: ground, width: RunnerLevel.pitWidth, height: floorHeight)) }
            figure.clip(to: visible)
        }

        let flip = level.facing == .left
        drawRows(sprite.body, at: CGPoint(x: level.x, y: top), flip: flip, in: &figure)
        let legs = level.isJumping
            ? sprite.leap
            : sprite.strides[reduceMotion ? 0 : Int(level.distance / (2 * px)) % sprite.strides.count]
        drawRows(legs, at: CGPoint(x: level.x, y: top + CGFloat(sprite.body.count) * px), flip: flip, in: &figure)

        if runner.pace(for: status).sweats {
            let bob: CGFloat = reduceMotion ? 0 : (Int(now.timeIntervalSinceReferenceDate * 4) % 2 == 0 ? 0 : px)
            let x = flip ? level.x + runner.width + px / 2 : level.x - px * 1.5
            figure.fill(Path(CGRect(x: x, y: top + 2 * px + bob, width: px, height: 2 * px)), with: .color(sprite.sweat))
        }

        if let rise = level.coinRise(at: now) {
            let coinWidth = CGFloat(sprite.coin.first?.count ?? 0) * px
            let origin = CGPoint(x: level.x + (runner.width - coinWidth) / 2,
                                 y: top - CGFloat(sprite.coin.count) * px - 4 - rise)
            drawRows(sprite.coin, at: origin, flip: false, in: &context)
        }
    }

    private func drawRows(_ rows: [String], at origin: CGPoint, flip: Bool, in context: inout GraphicsContext) {
        let px = runner.pixel
        for (row, line) in rows.enumerated() {
            let pixels = Array(line)
            for (column, character) in pixels.enumerated() {
                guard let color = runner.sprite.palette[character] else { continue }
                let x = flip ? pixels.count - 1 - column : column
                let rect = CGRect(x: (origin.x + CGFloat(x) * px).rounded(), y: (origin.y + CGFloat(row) * px).rounded(),
                                  width: px, height: px)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }

    private func drawGameOver(in context: inout GraphicsContext, at center: CGPoint) {
        let words = theme.statusWord(for: .depleted)
        let shadow = context.resolve(Text(words).font(theme.displayFont(size: 12)).foregroundStyle(theme.glassBorder))
        let face = context.resolve(Text(words).font(theme.displayFont(size: 12)).foregroundStyle(theme.glassBackground))
        context.draw(shadow, at: CGPoint(x: center.x + 1.5, y: center.y + 1.5))
        context.draw(face, at: center)
    }
}
