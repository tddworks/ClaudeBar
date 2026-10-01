import SwiftUI
import Domain
import Infrastructure

// MARK: - Theme Registry

/// Manages available themes in the application.
/// Follows the same pattern as `AIProviders` for provider registration.
///
/// ## Usage
/// ```swift
/// // Get a theme by ID
/// let theme = ThemeRegistry.shared.theme(for: "dark")
///
/// // Register a custom theme
/// ThemeRegistry.shared.register(MyCustomTheme())
///
/// // Get all available themes
/// let allThemes = ThemeRegistry.shared.allThemes
/// ```
@MainActor
public final class ThemeRegistry {
    /// Shared singleton instance
    public static let shared = ThemeRegistry()

    /// Registered themes keyed by ID
    private var themes: [String: any AppThemeProvider] = [:]

    /// Order of theme IDs for consistent display
    private var themeOrder: [String] = []

    private let importedThemeStore = ImportedThemeStore()

    /// Initialize with built-in themes
    private init() {
        registerBuiltInThemes()
        loadImportedThemes()
    }

    /// Register all built-in themes
    private func registerBuiltInThemes() {
        register(LightTheme())
        register(DarkTheme())
        register(SystemTheme())
        register(CLITheme())
        register(ChristmasTheme())
    }

    // MARK: - Public API

    /// Register a theme. If a theme with the same ID exists, it will be replaced.
    /// - Parameter theme: The theme to register
    public func register(_ theme: any AppThemeProvider) {
        let isNew = themes[theme.id] == nil
        themes[theme.id] = theme
        if isNew {
            themeOrder.append(theme.id)
        }
    }

    /// Get a theme by its ID
    /// - Parameter id: The theme ID
    /// - Returns: The theme if found, nil otherwise
    public func theme(for id: String) -> (any AppThemeProvider)? {
        themes[id]
    }

    /// All registered themes in registration order
    public var allThemes: [any AppThemeProvider] {
        themeOrder.compactMap { themes[$0] }
    }

    /// All theme IDs in registration order
    public var allThemeIds: [String] {
        themeOrder
    }

    /// The default theme (Dark)
    public var defaultTheme: any AppThemeProvider {
        themes["dark"] ?? DarkTheme()
    }

    /// Resolve a theme ID to a concrete theme, considering system theme and
    /// the user's status color policy.
    ///
    /// Wraps at resolve time, not registration: `isImported(id:)` and
    /// `removeImportedTheme(id:)` type-check the stored theme.
    ///
    /// - Parameters:
    ///   - id: The theme ID (may be "system")
    ///   - systemColorScheme: The current system color scheme
    ///   - statusColors: `.default` returns the stored theme untouched
    /// - Returns: The resolved theme
    public func resolveTheme(
        for id: String,
        systemColorScheme: ColorScheme,
        statusColors: StatusColorPolicy = .default
    ) -> any AppThemeProvider {
        let base: any AppThemeProvider
        if id == "system" {
            base = systemColorScheme == .dark ? (themes["dark"] ?? DarkTheme()) : (themes["light"] ?? LightTheme())
        } else {
            base = themes[id] ?? defaultTheme
        }
        guard statusColors.isActive else { return base }
        return StatusColorOverridingTheme(
            base: base,
            policy: statusColors,
            appearance: systemColorScheme == .dark ? .dark : .light
        )
    }

    // MARK: - Imported Themes

    /// Load imported themes from ~/.claudebar/themes/
    private func loadImportedThemes() {
        for (scheme, _) in importedThemeStore.loadAll() {
            let props = TerminalThemeGenerator.generate(from: scheme)
            let theme = ImportedTerminalTheme(props: props, scheme: scheme)
            register(theme)
        }
    }

    /// Import a `.itermcolors` file, persist the color scheme, and register the generated theme.
    /// - Parameter url: Path to the `.itermcolors` file.
    /// - Returns: The generated ``AppThemeProvider`` theme.
    /// - Throws: ``ITermColorsParserError`` if the file cannot be parsed.
    @discardableResult
    public func importItermcolors(from url: URL) throws -> any AppThemeProvider {
        let scheme = try ITermColorsParser.parse(from: url)
        try importedThemeStore.save(scheme)
        let props = TerminalThemeGenerator.generate(from: scheme)
        let theme = ImportedTerminalTheme(props: props, scheme: scheme)
        register(theme)
        return theme
    }

    /// Remove an imported theme by its ID. Built-in themes are not affected.
    /// - Parameter id: The theme ID (e.g., `"imported-dracula"`).
    public func removeImportedTheme(id: String) {
        guard let theme = themes[id], theme is ImportedTerminalTheme else { return }
        let displayName = theme.displayName
        themes.removeValue(forKey: id)
        themeOrder.removeAll { $0 == id }
        try? importedThemeStore.delete(name: displayName)
    }

    /// Whether a theme is imported (vs built-in).
    public func isImported(id: String) -> Bool {
        themes[id] is ImportedTerminalTheme
    }
}

// MARK: - System Theme (Special)

/// System theme that adapts to macOS appearance.
/// This is a placeholder - the actual resolution happens in ThemeRegistry.resolveTheme()
public struct SystemTheme: AppThemeProvider {
    public let id = "system"
    public let displayName = "System"
    public let icon = "circle.lefthalf.filled"

    // System theme delegates to Dark theme by default
    // The actual theme is resolved at runtime based on system appearance
    private let delegate = DarkTheme()

    public var backgroundGradient: LinearGradient { delegate.backgroundGradient }
    public var showBackgroundOrbs: Bool { delegate.showBackgroundOrbs }
    public var cardGradient: LinearGradient { delegate.cardGradient }
    public var glassBackground: Color { delegate.glassBackground }
    public var glassBorder: Color { delegate.glassBorder }
    public var glassHighlight: Color { delegate.glassHighlight }
    public var cardCornerRadius: CGFloat { delegate.cardCornerRadius }
    public var pillCornerRadius: CGFloat { delegate.pillCornerRadius }
    public var textPrimary: Color { delegate.textPrimary }
    public var textSecondary: Color { delegate.textSecondary }
    public var textTertiary: Color { delegate.textTertiary }
    public var fontDesign: Font.Design { delegate.fontDesign }
    public var statusHealthy: Color { delegate.statusHealthy }
    public var statusWarning: Color { delegate.statusWarning }
    public var statusCritical: Color { delegate.statusCritical }
    public var statusDepleted: Color { delegate.statusDepleted }
    public var accentPrimary: Color { delegate.accentPrimary }
    public var accentSecondary: Color { delegate.accentSecondary }
    public var accentGradient: LinearGradient { delegate.accentGradient }
    public var pillGradient: LinearGradient { delegate.pillGradient }
    public var shareGradient: LinearGradient { delegate.shareGradient }
    public var hoverOverlay: Color { delegate.hoverOverlay }
    public var pressedOverlay: Color { delegate.pressedOverlay }
    public var progressTrack: Color { delegate.progressTrack }
}
