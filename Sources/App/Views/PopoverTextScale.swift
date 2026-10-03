import SwiftUI
import Domain

// MARK: - Text Scale

extension PopoverTextSize {
    /// Multiplier applied to every point size in the popover.
    ///
    /// Domain models the user's choice; the concrete numbers are a rendering
    /// decision and live here, beside the wrapper that applies them — the same
    /// split `MenuBarStackedSize` has with the stacked menu bar's point sizes.
    var textScale: CGFloat {
        switch self {
        case .medium: 1.0
        case .large: 1.2
        case .extraLarge: 1.4
        }
    }

    /// `size` in points at this text size.
    func scaled(_ size: CGFloat) -> CGFloat {
        size * textScale
    }

    /// The width the popover draws at: text and window in step, so a line that
    /// fits at one size still fits at the next.
    ///
    /// Read from the same environment value as the fonts, so the frame can
    /// never size the window for a different size than the one it draws in.
    var popoverWidth: CGFloat {
        PopoverContentWidth.width(scale: textScale)
    }
}

// MARK: - Popover Text Size Environment Key

/// Environment key carrying the popover's text size down the view tree.
private struct PopoverTextSizeKey: EnvironmentKey {
    static let defaultValue: PopoverTextSize = .default
}

extension EnvironmentValues {
    /// The text size the popover renders at.
    ///
    /// Injected where the popover is hosted, so every popover view reads the
    /// user's choice from the environment instead of threading it through
    /// initializers.
    var popoverTextSize: PopoverTextSize {
        get { self[PopoverTextSizeKey.self] }
        set { self[PopoverTextSizeKey.self] = newValue }
    }
}

// MARK: - Font Wrapper

/// Applies one of the popover's point sizes, scaled by the user's choice.
///
/// macOS' Text Size accessibility setting cannot do this job: it rescales
/// *semantic* fonts only, and the popover names every size explicitly so the
/// layout stays the designer's. Scaling here keeps one scale factor for the
/// whole popover, and the width grows with it (`PopoverContentWidth`), so a line
/// that fits at one size still fits at the next.
struct PopoverFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design?
    @Environment(\.popoverTextSize) private var popoverTextSize

    /// The point size this modifier renders at for `textSize`.
    ///
    /// The scale is applied here and nowhere else, and `body` hands exactly
    /// this to `Font.system`, so the rendered size and the asserted size cannot
    /// drift apart.
    func pointSize(at textSize: PopoverTextSize) -> CGFloat {
        textSize.scaled(size)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: pointSize(at: popoverTextSize), weight: weight, design: design))
    }
}

/// Resolves a popover big number's size through the user's Text Size setting.
///
/// A theme may name its own typeface for these numbers (`displayFontName`, e.g.
/// the Pop theme's), so the size is scaled here and the typeface is still the
/// theme's decision. Scaling before the theme is asked keeps the two concerns
/// independent: the theme chooses *which* face, the setting chooses *how big*.
struct PopoverDisplayFontModifier: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let theme: any AppThemeProvider
    @Environment(\.popoverTextSize) private var popoverTextSize

    /// The point size this modifier asks the theme for, for `textSize`.
    func pointSize(at textSize: PopoverTextSize) -> CGFloat {
        textSize.scaled(size)
    }

    func body(content: Content) -> some View {
        content.font(theme.displayFont(size: pointSize(at: popoverTextSize), weight: weight))
    }
}

extension View {
    /// The theme's display font at a scaled `size`, for a popover big number.
    ///
    /// Use this instead of `popoverFont` wherever a number is drawn with
    /// `theme.displayFont(size:)`: the theme keeps its typeface, the user's
    /// Text Size setting still scales it.
    ///
    /// ## Usage
    /// ```swift
    /// Text(costUsage.formattedCost)
    ///     .popoverDisplayFont(size: 28, weight: .heavy, theme: theme)
    /// ```
    func popoverDisplayFont(
        size: CGFloat,
        weight: Font.Weight = .bold,
        theme: any AppThemeProvider
    ) -> some View {
        modifier(PopoverDisplayFontModifier(size: size, weight: weight, theme: theme))
    }
}

extension View {
    /// Popover text at `size` points, scaled by the user's Text Size setting.
    ///
    /// Every font carrying popover content goes through here, not just the quota
    /// cards: the header and provider pills, the session, cost and account
    /// cards, the usage-history chart, the embedded web card, and the
    /// share-pass overlays that cover the whole popover. A content font left
    /// behind here stays 8pt at Extra Large and leaves the setting
    /// half-applied.
    ///
    /// The one exception is `ProviderIconView`'s fallback glyph — the question
    /// mark drawn when a provider has no icon asset. It does not scale, because
    /// the circular badge it sits in is a fixed frame and a larger glyph would
    /// overflow it. It is decoration, not text anyone reads.
    ///
    /// A big number drawn with `theme.displayFont(size:)` goes through
    /// `popoverDisplayFont(size:weight:theme:)` instead, so the scale applies
    /// to the size while the theme keeps its typeface.
    ///
    /// ## Usage
    /// ```swift
    /// Text("SESSION")
    ///     .popoverFont(8, weight: .medium, design: theme.fontDesign)
    /// ```
    func popoverFont(
        _ size: CGFloat,
        weight: Font.Weight? = nil,
        design: Font.Design? = nil
    ) -> some View {
        modifier(PopoverFontModifier(size: size, weight: weight, design: design))
    }
}
