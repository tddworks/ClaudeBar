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
    var displayFontName: String? { base.displayFontName }
    var displayFontScale: CGFloat { base.displayFontScale }
    var cardBorderWidth: CGFloat { base.cardBorderWidth }
    var cardShadow: ThemeShadow? { base.cardShadow }
    var textOnStatus: Color { base.textOnStatus }
    var progressStyle: ProgressStyle { base.progressStyle }
    func statusWord(for status: QuotaStatus) -> String { base.statusWord(for: status) }
    func badgeFont(size: CGFloat) -> Font { base.badgeFont(size: size) }
    var tagline: String? { base.tagline }
    var textStyleName: String? { base.textStyleName }
    var controlCornerRadius: CGFloat? { base.controlCornerRadius }
    var groundHeight: CGFloat { base.groundHeight }
    var headerStyle: HeaderStyle { base.headerStyle }
    var runner: GroundRunner? { base.runner }
    func walking(_ shown: Bool) -> any AppThemeProvider {
        StatusColorOverridingTheme(base: base.walking(shown), policy: policy, appearance: appearance)
    }
    func blinks(_ status: QuotaStatus) -> Bool { base.blinks(status) }
    var textOnAccent: Color { base.textOnAccent }
    var badgeCornerRadius: CGFloat? { base.badgeCornerRadius }
    var cardRivetSize: CGFloat? { base.cardRivetSize }

    // MARK: Status Colors

    var statusHealthy: Color { resolved(.healthy) ?? base.statusHealthy }
    var statusWarning: Color { resolved(.warning) ?? base.statusWarning }
    var statusCritical: Color { resolved(.critical) ?? base.statusCritical }
    var statusDepleted: Color { resolved(.depleted) ?? base.statusDepleted }

    /// A colour the person chose wins in the menu bar too; otherwise the
    /// theme's own menu-bar colour.
    func menuBarStatusColor(for status: QuotaStatus, darkMenuBar: Bool) -> Color {
        resolved(status) ?? base.menuBarStatusColor(for: status, darkMenuBar: darkMenuBar)
    }

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
