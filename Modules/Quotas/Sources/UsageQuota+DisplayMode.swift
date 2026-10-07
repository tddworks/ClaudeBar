import Foundation

// How a quota reads under the person's display mode — page state (CANONICAL_MODEL §6).
extension UsageQuota {
    /// The headline percentage for the display mode.
    public func displayPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining, .pace: percentRemaining
        case .used: percentUsed
        }
    }

    /// The bar's fill, on the headline number's scale.
    public func displayProgressPercent(mode: UsageDisplayMode) -> Double {
        switch mode {
        case .remaining, .pace: percentRemaining
        case .used: percentUsed
        }
    }

    /// Where the bar would sit if usage were spread evenly across the window.
    public func expectedProgressPercent(mode: UsageDisplayMode) -> Double? {
        guard let percentTimeElapsed else { return nil }
        switch mode {
        case .remaining, .pace: return 100 - percentTimeElapsed
        case .used: return percentTimeElapsed
        }
    }

    /// Tooltip copy for the pace tick under the bar.
    public func paceTickHelp(mode: UsageDisplayMode) -> String? {
        guard let expected = expectedProgressPercent(mode: mode) else { return nil }
        let base = switch mode {
        case .used:
            "Pace marker: steady usage would have used ~\(Int(expected.rounded()))% by now"
        case .remaining, .pace:
            "Pace marker: steady usage would leave ~\(Int(expected.rounded()))% remaining by now"
        }
        guard let insight = paceInsight else { return base + "." }
        return base + " — " + insight.prefix(1).lowercased() + insight.dropFirst() + "."
    }
}
