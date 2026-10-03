import Quotas
import DataSources
import Providers
import Foundation

/// Width policy for the popover itself.
///
/// Pure math, kept in Domain beside `PopoverContentHeight` so it is
/// unit-testable. The popover's fonts are pinned point sizes, so bigger text
/// needs a wider window to keep the same line lengths — the width counterpart
/// of the content region's height cap.
public enum PopoverContentWidth {
    /// The popover's width at the default text size: the width it has always
    /// had, and the narrowest it ever gets.
    public static let base: CGFloat = 400

    /// Width for a text `scale`. Text and width grow together, so a line that
    /// fits at one size still fits at the next instead of truncating.
    /// - Parameter scale: multiplier applied to every popover font, from
    ///   `PopoverTextSize`'s rendering mapping in the App layer.
    public static func width(scale: CGFloat) -> CGFloat {
        base * scale
    }
}
