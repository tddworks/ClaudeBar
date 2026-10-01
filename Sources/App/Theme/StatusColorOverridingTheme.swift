import SwiftUI
import Domain

/// Forwards everything to `base` except the four status colors, which come
/// from `policy`. Built only by `ThemeRegistry.resolveTheme`.
///
/// `statusColor(for:)` and `progressGradient(for:)` are intentionally left
/// to the protocol defaults so they derive from the overridden colors; a
/// theme with its own `progressGradient` (CLI) loses it while overrides are
/// active.
struct StatusColorOverridingTheme: AppThemeProvider {
    let base: any AppThemeProvider
    let policy: StatusColorPolicy
    let appearance: ColorAppearance

    // MARK: Identity

    var id: String { base.id }
    var displayName: String { base.displayName }
    var icon: String { base.icon }
    var subtitle: String? { base.subtitle }
    var statusBarIconName: String? { base.statusBarIconName }

    // MARK: Background

    var backgroundGradient: LinearGradient { base.backgroundGradient }
    var showBackgroundOrbs: Bool { base.showBackgroundOrbs }
    @MainActor var overlayView: AnyView? { base.overlayView }

    // MARK: Cards & Glass

    var cardGradient: LinearGradient { base.cardGradient }
    var glassBackground: Color { base.glassBackground }
    var glassBorder: Color { base.glassBorder }
    var glassHighlight: Color { base.glassHighlight }
    var cardCornerRadius: CGFloat { base.cardCornerRadius }
    var pillCornerRadius: CGFloat { base.pillCornerRadius }

    // MARK: Typography

    var textPrimary: Color { base.textPrimary }
    var textSecondary: Color { base.textSecondary }
    var textTertiary: Color { base.textTertiary }
    var fontDesign: Font.Design { base.fontDesign }
    var customFontName: String? { base.customFontName }

    // MARK: Status Colors

    var statusHealthy: Color { resolved(.healthy) ?? base.statusHealthy }
    var statusWarning: Color { resolved(.warning) ?? base.statusWarning }
    var statusCritical: Color { resolved(.critical) ?? base.statusCritical }
    var statusDepleted: Color { resolved(.depleted) ?? base.statusDepleted }

    private func resolved(_ status: QuotaStatus) -> Color? {
        policy.color(for: status, appearance: appearance).map { Color($0) }
    }

    // MARK: Accents

    var accentPrimary: Color { base.accentPrimary }
    var accentSecondary: Color { base.accentSecondary }
    var accentGradient: LinearGradient { base.accentGradient }
    var pillGradient: LinearGradient { base.pillGradient }
    var shareGradient: LinearGradient { base.shareGradient }

    // MARK: Interactive States

    var hoverOverlay: Color { base.hoverOverlay }
    var pressedOverlay: Color { base.pressedOverlay }

    // MARK: Progress Bar

    var progressTrack: Color { base.progressTrack }
}
