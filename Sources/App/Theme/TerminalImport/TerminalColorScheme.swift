import Foundation

/// Format-agnostic representation of a terminal color scheme.
///
/// Holds 16 ANSI colors plus UI colors (background, foreground, cursor, selection).
/// `Codable` for JSON persistence in `~/.claudebar/themes/`.
/// Decoupled from SwiftUI to keep it in the Infrastructure layer.
public struct TerminalColorScheme: Codable, Sendable, Equatable {
    public let name: String
    public let background: RGBColor
    public let foreground: RGBColor
    public let boldText: RGBColor?
    public let cursor: RGBColor?
    public let selection: RGBColor?
    public let selectionText: RGBColor?
    public let ansiColors: [RGBColor]

    /// Whether this scheme has exactly 16 ANSI colors (required for theme generation).
    public var isValid: Bool {
        ansiColors.count == 16
    }

    public init(
        name: String,
        background: RGBColor,
        foreground: RGBColor,
        boldText: RGBColor?,
        cursor: RGBColor?,
        selection: RGBColor?,
        selectionText: RGBColor?,
        ansiColors: [RGBColor]
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.boldText = boldText
        self.cursor = cursor
        self.selection = selection
        self.selectionText = selectionText
        self.ansiColors = ansiColors
    }

    // ANSI color semantic accessors (indices 0-15)

    /// ANSI 0: Black
    public var black: RGBColor { ansiColors[0] }
    public var red: RGBColor { ansiColors[1] }
    public var green: RGBColor { ansiColors[2] }
    public var yellow: RGBColor { ansiColors[3] }
    public var blue: RGBColor { ansiColors[4] }
    public var magenta: RGBColor { ansiColors[5] }
    public var cyan: RGBColor { ansiColors[6] }
    public var white: RGBColor { ansiColors[7] }
    public var brightBlack: RGBColor { ansiColors[8] }
    public var brightRed: RGBColor { ansiColors[9] }
    public var brightGreen: RGBColor { ansiColors[10] }
    public var brightYellow: RGBColor { ansiColors[11] }
    public var brightBlue: RGBColor { ansiColors[12] }
    public var brightMagenta: RGBColor { ansiColors[13] }
    public var brightCyan: RGBColor { ansiColors[14] }
    public var brightWhite: RGBColor { ansiColors[15] }

    /// Whether this scheme has a dark background (luminance < 0.5).
    public var isDark: Bool {
        background.luminance < 0.5
    }
}

// MARK: - RGBColor

extension TerminalColorScheme {
    /// A color represented as red, green, blue, and alpha components (0.0–1.0).
    public struct RGBColor: Codable, Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Relative luminance per ITU-R BT.709.
        public var luminance: Double {
            0.2126 * red + 0.7152 * green + 0.0722 * blue
        }

        /// Returns a new color lightened by the given fraction (0.0–1.0).
        public func lightened(by amount: Double) -> RGBColor {
            RGBColor(
                red: min(1.0, red + (1.0 - red) * amount),
                green: min(1.0, green + (1.0 - green) * amount),
                blue: min(1.0, blue + (1.0 - blue) * amount),
                alpha: alpha
            )
        }

        /// Returns a new color darkened by the given fraction (0.0–1.0).
        public func darkened(by amount: Double) -> RGBColor {
            RGBColor(
                red: max(0.0, red * (1.0 - amount)),
                green: max(0.0, green * (1.0 - amount)),
                blue: max(0.0, blue * (1.0 - amount)),
                alpha: alpha
            )
        }

        /// Returns a new color with the given alpha value.
        public func withAlpha(_ alpha: Double) -> RGBColor {
            RGBColor(red: red, green: green, blue: blue, alpha: alpha)
        }
    }
}
