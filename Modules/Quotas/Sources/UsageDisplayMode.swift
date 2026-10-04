import Foundation

/// Controls whether quota percentages are displayed as "remaining", "used", or "pace".
///
/// - `.remaining`: Shows how much quota is left (e.g., "25% Remaining")
/// - `.used`: Shows how much quota has been consumed (e.g., "75% Used")
/// - `.pace`: Shows how far ahead/behind expected usage pace (e.g., "20% Ahead")
///
/// - Note: Interim — today's shape, moved unchanged into the kernel.
///   Final version (docs/architecture/CANONICAL_MODEL.md) — leaves the kernel for the App: how a percentage is shown is page state (§6).
public enum UsageDisplayMode: String, Sendable, Equatable, CaseIterable {
    case remaining
    case used
    case pace

    /// The label shown alongside the percentage in quota cards.
    public var displayLabel: String {
        switch self {
        case .remaining: "Remaining"
        case .used: "Used"
        case .pace: "Remaining"
        }
    }
}