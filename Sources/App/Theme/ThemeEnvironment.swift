import SwiftUI

// MARK: - Theme Environment Key

/// Environment key for injecting the active theme into the view hierarchy.
private struct AppThemeKey: EnvironmentKey {
    nonisolated(unsafe) static var defaultValue: any AppThemeProvider = DarkTheme()
}

extension EnvironmentValues {
    /// The active theme for the current view hierarchy.
    ///
    /// ## Usage
    /// ```swift
    /// struct MyView: View {
    ///     @Environment(\.appTheme) var theme
    ///
    ///     var body: some View {
    ///         Text("Hello")
    ///             .foregroundColor(theme.textPrimary)
    ///     }
    /// }
    /// ```
    public var appTheme: any AppThemeProvider {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

// MARK: - Theme Provider Modifier

/// View modifier that provides the resolved theme to the view hierarchy.
///
/// ## Usage
/// ```swift
/// ContentView()
///     .appThemeProvider(themeMode: settings.themeMode)
/// ```
public struct AppThemeProviderModifier: ViewModifier {
    let themeModeId: String
    @Environment(\.colorScheme) private var systemColorScheme

    public init(themeModeId: String) {
        self.themeModeId = themeModeId
    }

    @MainActor
    private var resolvedTheme: any AppThemeProvider {
        ThemeRegistry.shared.resolveTheme(for: themeModeId, systemColorScheme: systemColorScheme)
    }

    private var effectiveColorScheme: ColorScheme {
        let mode = ThemeMode(rawValue: themeModeId)
        switch mode {
        case .light: return .light
        case .dark, .cli, .christmas: return .dark
        case .system: return systemColorScheme
        case .none:
            // Imported theme — check dark preference
            if let imported = ThemeRegistry.shared.theme(for: themeModeId) as? ImportedTerminalTheme {
                return imported.prefersDarkColorScheme ? .dark : .light
            }
            return systemColorScheme
        }
    }

    public func body(content: Content) -> some View {
        content
            .environment(\.appTheme, resolvedTheme)
            .environment(\.colorScheme, effectiveColorScheme)
    }
}

extension View {
    /// Applies the theme provider modifier to inject the active theme.
    /// - Parameter themeModeId: The theme mode ID from AppSettings
    /// - Returns: A view with the theme environment set
    public func appThemeProvider(themeModeId: String) -> some View {
        modifier(AppThemeProviderModifier(themeModeId: themeModeId))
    }
}

// MARK: - Convenience View Extensions

extension View {
    /// Applies the theme's text primary color
    @MainActor
    public func themeTextPrimary() -> some View {
        modifier(ThemeTextModifier(style: .primary))
    }

    /// Applies the theme's text secondary color
    @MainActor
    public func themeTextSecondary() -> some View {
        modifier(ThemeTextModifier(style: .secondary))
    }

    /// Applies the theme's text tertiary color
    @MainActor
    public func themeTextTertiary() -> some View {
        modifier(ThemeTextModifier(style: .tertiary))
    }

    /// Applies the theme's card styling
    @MainActor
    public func themeCard() -> some View {
        modifier(ThemeCardModifier())
    }
}

// MARK: - Theme Text Modifier

private struct ThemeTextModifier: ViewModifier {
    enum Style { case primary, secondary, tertiary }
    let style: Style
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundColor(color)
    }

    private var color: Color {
        switch style {
        case .primary: theme.textPrimary
        case .secondary: theme.textSecondary
        case .tertiary: theme.textTertiary
        }
    }
}

// MARK: - Theme Card Modifier

private struct ThemeCardModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                            .stroke(theme.glassBorder, lineWidth: 1)
                    )
            )
    }
}
