import Foundation

/// The accent color ClaudeBar sends to Notify! for a quota status.
///
/// These are the same four colors the Mac uses (`BaseTheme.defaultStatus*`),
/// written as hex because Domain has no view layer and the gateway wants
/// `#RRGGBB` anyway. Keeping them in step means a quota that looks critical in
/// the menu bar looks critical on the Lock Screen.
public extension QuotaStatus {
    var notifyTintHex: String {
        switch self {
        case .healthy: "#59EBAD"
        case .warning: "#FAB859"
        case .critical: "#FA6B85"
        case .depleted: "#D94059"
        }
    }
}

/// SF Symbols ClaudeBar asks Notify! to draw. Named here rather than inline so
/// the tile and the widget cannot drift apart.
public enum NotifySymbol {
    /// The tile and widget icon. A gauge reads correctly at both sizes and does
    /// not imply a direction of travel the way an arrow would.
    public static let quota = "gauge.with.needle"
}
