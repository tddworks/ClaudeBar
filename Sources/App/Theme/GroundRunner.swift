import SwiftUI
import Domain

/// A runner on a theme's floor: it shows the selected provider's status by
/// how it moves, and jumps for a coin when a refresh finishes. Nobody plays
/// it. Moment to moment it is a `RunnerLevel`; `GroundRunnerView` draws it.
public struct GroundRunner: Sendable {
    /// The lane above the floor it walks in; the action bar stands on top.
    public let laneHeight: CGFloat
    /// One art pixel, in points.
    public let pixel: CGFloat
    public let sprite: RunnerSprite
    private let paces: [QuotaStatus: RunnerPace]

    public init(laneHeight: CGFloat, pixel: CGFloat, sprite: RunnerSprite, paces: [QuotaStatus: RunnerPace]) {
        self.laneHeight = laneHeight
        self.pixel = pixel
        self.sprite = sprite
        self.paces = paces
    }

    /// How it moves while a provider is `status`.
    public func pace(for status: QuotaStatus) -> RunnerPace {
        paces[status] ?? .walk
    }

    /// Its width on screen.
    public var width: CGFloat { CGFloat(sprite.body.first?.count ?? 0) * pixel }
}

/// How the runner moves.
public enum RunnerPace: Equatable, Sendable {
    case stroll, walk, run
    /// It stops, a pit opens under it, and it falls in: GAME OVER.
    case fall

    public var pointsPerSecond: CGFloat {
        switch self {
        case .stroll: 16
        case .walk: 30
        case .run: 66
        case .fall: 0
        }
    }

    /// A drop of sweat flies off it.
    public var sweats: Bool { self == .run }
}

/// The runner's pixel art, facing right: one character per art pixel, `.`
/// for none, each other character a colour from `palette`.
public struct RunnerSprite: Sendable {
    /// Head and body, above the legs.
    public let body: [String]
    /// The legs' walking frames, taken in turn.
    public let strides: [[String]]
    /// The legs in the air.
    public let leap: [String]
    /// The coin that pops over its head.
    public let coin: [String]
    public let palette: [Character: Color]
    /// The drop of sweat while it runs.
    public let sweat: Color

    public init(body: [String], strides: [[String]], leap: [String], coin: [String], palette: [Character: Color], sweat: Color) {
        self.body = body
        self.strides = strides
        self.leap = leap
        self.coin = coin
        self.palette = palette
        self.sweat = sweat
    }

    /// How tall it stands, in art pixels.
    public var rows: Int { body.count + (strides.first?.count ?? 0) }
}
