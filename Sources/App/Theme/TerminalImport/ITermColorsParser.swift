import Foundation

/// Errors thrown when parsing `.itermcolors` files.
public enum ITermColorsParserError: Error, Equatable {
    /// The data is not a valid property list.
    case invalidPlist
    /// A required color key is missing from the plist.
    case missingColor(String)
}

/// Parses `.itermcolors` XML plist files into ``TerminalColorScheme``.
///
/// The `.itermcolors` format is an XML property list where each color key maps to a dictionary
/// with `Red Component`, `Green Component`, `Blue Component` (floats 0.0–1.0), and optional
/// `Alpha Component` and `Color Space`. This is the standard export format from iTerm2
/// (Preferences > Profiles > Colors > Color Presets > Export).
///
/// Uses Foundation's `PropertyListSerialization` — no external dependencies required.
public struct ITermColorsParser {

    /// Parse a `.itermcolors` file at the given URL. The theme name is derived from the filename.
    public static func parse(from url: URL) throws -> TerminalColorScheme {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        return try parse(from: data, name: name)
    }

    /// Parse `.itermcolors` data with an explicit theme name.
    /// - Throws: ``ITermColorsParserError`` if required colors are missing or data is not a valid plist.
    public static func parse(from data: Data, name: String) throws -> TerminalColorScheme {
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw ITermColorsParserError.invalidPlist
        }

        let background = try extractColor(from: plist, key: "Background Color")
        let foreground = try extractColor(from: plist, key: "Foreground Color")
        let boldText = try? extractColor(from: plist, key: "Bold Color")
        let cursor = try? extractColor(from: plist, key: "Cursor Color")
        let selection = try? extractColor(from: plist, key: "Selection Color")
        let selectionText = try? extractColor(from: plist, key: "Selected Text Color")

        var ansiColors: [TerminalColorScheme.RGBColor] = []
        for i in 0..<16 {
            let color = try extractColor(from: plist, key: "Ansi \(i) Color")
            ansiColors.append(color)
        }

        return TerminalColorScheme(
            name: name,
            background: background,
            foreground: foreground,
            boldText: boldText,
            cursor: cursor,
            selection: selection,
            selectionText: selectionText,
            ansiColors: ansiColors
        )
    }

    private static func extractColor(
        from plist: [String: Any],
        key: String
    ) throws -> TerminalColorScheme.RGBColor {
        guard let colorDict = plist[key] as? [String: Any] else {
            throw ITermColorsParserError.missingColor(key)
        }
        let red = (colorDict["Red Component"] as? Double) ?? 0.0
        let green = (colorDict["Green Component"] as? Double) ?? 0.0
        let blue = (colorDict["Blue Component"] as? Double) ?? 0.0
        let alpha = (colorDict["Alpha Component"] as? Double) ?? 1.0
        return TerminalColorScheme.RGBColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
