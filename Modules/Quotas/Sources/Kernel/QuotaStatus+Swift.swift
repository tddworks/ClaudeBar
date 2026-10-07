import QuotaKernel

extension QuotaStatus: @retroactive Comparable {
    /// The status for the percentage left.
    public static func from(percentRemaining: Double) -> QuotaStatus {
        QuotaStatus.companion.from(percentRemaining: percentRemaining)
    }

    /// The pace-aware status from the projected end-of-period usage.
    public static func from(
        percentRemaining: Double,
        percentTimeElapsed: Double,
        burnRateThreshold: Double
    ) -> QuotaStatus {
        QuotaStatus.companion.from(
            percentRemaining: percentRemaining,
            percentTimeElapsed: percentTimeElapsed,
            burnRateThreshold: burnRateThreshold
        )
    }

    /// Severity order: healthy < warning < critical < depleted.
    public static func < (lhs: QuotaStatus, rhs: QuotaStatus) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

extension UsagePace {
    public static func from(percentUsed: Double, percentTimeElapsed: Double) -> UsagePace {
        UsagePace.companion.from(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed)
    }

    /// SF Symbol for this pace.
    public var symbolName: String {
        switch self {
        case .onPace: "equal.circle.fill"
        case .ahead: "hare.fill"
        case .behind: "tortoise.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

extension PaceLevel: @retroactive Comparable {
    /// The level for this usage, or nil before 3% of the period has elapsed or once it is over.
    public static func from(percentUsed: Double, percentTimeElapsed: Double) -> PaceLevel? {
        PaceLevel.companion.from(percentUsed: percentUsed, percentTimeElapsed: percentTimeElapsed)
    }

    public var rawValue: Int { Int(ordinal) }

    public init?(rawValue: Int) {
        guard let level = PaceLevel.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = level
    }

    public static func < (lhs: PaceLevel, rhs: PaceLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}
