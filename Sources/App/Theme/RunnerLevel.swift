import Foundation
import CoreGraphics

/// The runner moment to moment: where it is on the floor, which way it
/// faces, how high it jumps and whether it has fallen in a pit. The view
/// tells it the time, the pace and the lane's width, and draws what it says.
final class RunnerLevel {
    enum Facing: Equatable { case left, right }

    /// The space it keeps from either end of the lane.
    static let margin: CGFloat = 6
    /// The most time one step covers, so a popover opened after a while
    /// doesn't send the runner across the lane at once.
    static let longestStep: TimeInterval = 0.1
    /// A pit is one brick wide.
    static let pitWidth: CGFloat = 36

    private static let jumpSpeed: CGFloat = 150
    private static let gravity: CGFloat = 520
    private static let pause: TimeInterval = 0.45
    private static let fallTime: TimeInterval = 0.6
    private static let coinTime: TimeInterval = 0.7
    private static let stillCoinTime: TimeInterval = 1.2
    private static let coinRise: CGFloat = 16

    private enum Phase: Equatable {
        case walking
        case entering
        case stopping(since: Date)
        case falling(since: Date)
        case gameOver
    }

    private(set) var x: CGFloat
    private(set) var facing: Facing = .right
    /// How far it has walked, which picks the legs' frame.
    private(set) var distance: CGFloat = 0
    /// Its height above the floor; below zero while it falls.
    private(set) var lift: CGFloat = 0
    /// The left edge of the pit it fell in.
    private(set) var pit: CGFloat?

    private let spriteWidth: CGFloat
    private var phase: Phase = .walking
    private var jumpedAt: Date?
    private var coin: (since: Date, still: Bool)?
    private var lastTick: Date?

    init(spriteWidth: CGFloat, x: CGFloat = margin) {
        self.spriteWidth = spriteWidth
        self.x = x
    }

    var isGameOver: Bool { phase == .gameOver }
    /// It is on the floor, or jumping above it.
    var isRunning: Bool { phase == .walking || phase == .entering }
    var isJumping: Bool { jumpedAt != nil }

    /// Moves it on to `now`.
    func advance(to now: Date, pace: RunnerPace, width: CGFloat, reduceMotion: Bool = false) {
        let step = lastTick.map { min(Self.longestStep, max(0, now.timeIntervalSince($0))) } ?? 0
        lastTick = now

        if pace == .fall {
            fall(at: now, reduceMotion: reduceMotion)
            return
        }
        if !isRunning { enter() }

        if !reduceMotion { walk(CGFloat(step) * pace.pointsPerSecond, width: width) }
        lift = jumpHeight(at: now)
    }

    /// A refresh finished: it jumps, and a coin pops over its head.
    func celebrate(at now: Date, reduceMotion: Bool = false) {
        guard isRunning else { return }
        coin = (now, reduceMotion)
        if !reduceMotion, jumpedAt == nil { jumpedAt = now }
    }

    /// How far the coin has risen over its head; `nil` once it has gone.
    func coinRise(at now: Date) -> CGFloat? {
        guard let coin else { return nil }
        let age = now.timeIntervalSince(coin.since)
        guard age < (coin.still ? Self.stillCoinTime : Self.coinTime) else { return nil }
        return coin.still ? 0 : Self.coinRise * CGFloat(min(1, age / 0.35))
    }

    private func walk(_ points: CGFloat, width: CGFloat) {
        let lowest = Self.margin, highest = max(lowest, width - spriteWidth - Self.margin)
        x += facing == .right ? points : -points
        distance += points
        if x > highest { x = highest; facing = .left }
        if phase == .entering {
            if x >= lowest { phase = .walking }
        } else if x < lowest {
            x = lowest; facing = .right
        }
    }

    private func jumpHeight(at now: Date) -> CGFloat {
        guard let jumpedAt else { return 0 }
        let t = CGFloat(now.timeIntervalSince(jumpedAt))
        let height = Self.jumpSpeed * t - Self.gravity * t * t / 2
        if height <= 0, t > 0 { self.jumpedAt = nil; return 0 }
        return max(0, height)
    }

    private func fall(at now: Date, reduceMotion: Bool) {
        jumpedAt = nil
        coin = nil
        switch phase {
        case .walking, .entering:
            lift = 0
            phase = reduceMotion ? .gameOver : .stopping(since: now)
            if reduceMotion { openPit() }
        case .stopping(let since) where now.timeIntervalSince(since) >= Self.pause:
            openPit()
            phase = .falling(since: now)
        case .falling(let since):
            let t = CGFloat(now.timeIntervalSince(since))
            lift = -Self.gravity * t * t / 2
            if t >= CGFloat(Self.fallTime) { phase = .gameOver }
        default:
            break
        }
    }

    /// A pit one brick wide under its feet, and it drops into the middle.
    private func openPit() {
        let brick = Self.pitWidth
        let left = ((x + spriteWidth / 2) / brick).rounded(.down) * brick
        pit = left
        x = left + (brick - spriteWidth) / 2
    }

    /// A new runner walks in from the left.
    private func enter() {
        phase = .entering
        pit = nil
        lift = 0
        x = -spriteWidth
        facing = .right
    }
}
