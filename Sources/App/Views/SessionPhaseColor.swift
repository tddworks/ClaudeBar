import SwiftUI
import Domain

extension ClaudeSession.Phase {
    /// The display color for this session phase.
    /// Single source of truth — used by StatusBarIcon, SessionIndicatorView, etc.
    /// Needs you is the loudest; Done recedes (docs/features/session-hooks/design.md).
    var color: Color {
        switch self {
        case .active: return .green
        case .subagentsWorking: return .blue
        case .awaitingInput: return .red
        case .stopped: return .gray
        case .ended: return .gray
        }
    }
}

extension AppThemeProvider {
    /// A phase in this theme's own palette, for cards that sit beside the
    /// quota cards: Needs you takes the theme's critical colour, Working its
    /// healthy one, Agents working its accent, and Done recedes.
    func color(for phase: ClaudeSession.Phase) -> Color {
        switch phase {
        case .awaitingInput: statusCritical
        case .subagentsWorking: accentPrimary
        case .active: statusHealthy
        case .stopped, .ended: textTertiary
        }
    }
}
