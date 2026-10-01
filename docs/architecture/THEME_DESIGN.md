# Theme System Design

This document describes the pluggable theme architecture in ClaudeBar.

## Overview

ClaudeBar uses a **protocol-based theme system** that allows easy creation and registration of new themes. The design follows the same patterns used throughout the codebase (ISP, Protocol-Based DI).

## Architecture

```
Sources/App/Theme/
├── AppThemeProvider.swift      # Protocol definition + BaseTheme
├── ThemeRegistry.swift         # Theme management
├── ThemeEnvironment.swift      # SwiftUI environment key + modifiers
└── Themes/
    ├── DarkTheme.swift         # Default dark theme
    ├── LightTheme.swift        # Light theme
    ├── CLITheme.swift          # Terminal-style theme
    └── ChristmasTheme.swift    # Festive holiday theme
```

## Core Components

### 1. AppThemeProvider Protocol

The `AppThemeProvider` protocol defines what every theme must provide:

```swift
public protocol AppThemeProvider {
    // Identity
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }
    var subtitle: String? { get }

    // Background
    var backgroundGradient: LinearGradient { get }
    var showBackgroundOrbs: Bool { get }
    var overlayView: AnyView? { get }

    // Cards & Glass
    var cardGradient: LinearGradient { get }
    var glassBackground: Color { get }
    var glassBorder: Color { get }
    var glassHighlight: Color { get }
    var cardCornerRadius: CGFloat { get }
    var pillCornerRadius: CGFloat { get }

    // Typography
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }
    var fontDesign: Font.Design { get }

    // Status Colors
    var statusHealthy: Color { get }
    var statusWarning: Color { get }
    var statusCritical: Color { get }
    var statusDepleted: Color { get }

    // Accents
    var accentPrimary: Color { get }
    var accentSecondary: Color { get }
    var accentGradient: LinearGradient { get }
    var pillGradient: LinearGradient { get }
    var shareGradient: LinearGradient { get }

    // Interactive States
    var hoverOverlay: Color { get }
    var pressedOverlay: Color { get }

    // Progress Bar
    var progressTrack: Color { get }

    // Computed Helpers
    func statusColor(for status: QuotaStatus) -> Color
    func progressGradient(for percent: Double) -> LinearGradient
}
```

### 2. ThemeRegistry

The `ThemeRegistry` manages all available themes:

```swift
@MainActor
public final class ThemeRegistry {
    public static let shared = ThemeRegistry()

    // Register a custom theme
    public func register(_ theme: any AppThemeProvider)

    // Get theme by ID
    public func theme(for id: String) -> (any AppThemeProvider)?

    // Get all themes
    public var allThemes: [any AppThemeProvider]

    // Resolve theme considering system appearance
    public func resolveTheme(for id: String, systemColorScheme: ColorScheme) -> any AppThemeProvider
}
```

### 3. Environment Injection

Themes are injected via SwiftUI environment:

```swift
// In views:
@Environment(\.appTheme) var theme

Text("Hello")
    .foregroundStyle(theme.textPrimary)
    .font(.system(size: 14, design: theme.fontDesign))
```

## Built-in Themes

| Theme | ID | Description |
|-------|-----|-------------|
| Dark | `dark` | Purple-pink gradients with glassmorphism |
| Light | `light` | Soft purple-pink tones for bright environments |
| CLI | `cli` | Minimalistic terminal aesthetic with green accents |
| Christmas | `christmas` | Festive red/green/gold with snowfall |
| System | `system` | Follows macOS appearance (resolves to Light or Dark) |

## Creating a New Theme

### Step 1: Create Theme File

Create a new file in `Sources/App/Theme/Themes/`:

```swift
// Sources/App/Theme/Themes/NeonTheme.swift
import SwiftUI

public struct NeonTheme: AppThemeProvider {
    // MARK: - Identity
    public let id = "neon"
    public let displayName = "Neon"
    public let icon = "lightbulb.fill"
    public let subtitle: String? = "Cyberpunk"

    // MARK: - Colors
    private let neonPink = Color(red: 1.0, green: 0.0, blue: 0.5)
    private let neonCyan = Color(red: 0.0, green: 1.0, blue: 1.0)
    private let neonPurple = Color(red: 0.5, green: 0.0, blue: 1.0)

    // MARK: - Background
    public var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.black, neonPurple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var showBackgroundOrbs: Bool { true }

    // ... implement all other required properties

    public init() {}
}
```

### Step 2: Register Theme

Add to `ThemeRegistry.registerBuiltInThemes()`:

```swift
private func registerBuiltInThemes() {
    register(LightTheme())
    register(DarkTheme())
    register(SystemTheme())
    register(CLITheme())
    register(ChristmasTheme())
    register(NeonTheme())  // Add your theme
}
```

### Step 3: Add to ThemeMode (Optional)

If you want the theme in the picker, add to `ThemeMode` enum in `Theme.swift`:

```swift
enum ThemeMode: String, CaseIterable {
    case light
    case dark
    case system
    case cli
    case neon      // Add case
    case christmas

    var displayName: String {
        switch self {
        // ...
        case .neon: "Neon"
        // ...
        }
    }
}
```

## Importing Terminal Themes

ClaudeBar can import `.itermcolors` files to automatically generate themes from terminal color schemes. Over 450 pre-made schemes are available at [iTerm2-Color-Schemes](https://github.com/mbadolato/iTerm2-Color-Schemes).

### How It Works

1. **Parse** — `ITermColorsParser` reads the XML plist, extracting 16 ANSI colors + background/foreground
2. **Generate** — `TerminalThemeGenerator` maps ANSI colors to `AppThemeProvider` properties:
   - ANSI Red → `statusCritical`
   - ANSI Green → `statusHealthy`
   - ANSI Yellow → `statusWarning`
   - ANSI Cyan → `accentPrimary`
   - ANSI Blue → `accentSecondary`
   - Background → `backgroundGradient`, derived card/glass colors
   - Foreground → `textPrimary`/`textSecondary`/`textTertiary`
3. **Persist** — Schemes are saved as JSON in `~/.claudebar/themes/`
4. **Register** — On launch, stored schemes are re-generated and registered in `ThemeRegistry`

### Files

| Component | Location |
|-----------|----------|
| Color model | `Sources/Infrastructure/TerminalImport/TerminalColorScheme.swift` |
| Parser | `Sources/Infrastructure/TerminalImport/ITermColorsParser.swift` |
| Generator | `Sources/Infrastructure/TerminalImport/TerminalThemeGenerator.swift` |
| Theme | `Sources/App/Theme/ImportedTerminalTheme.swift` |
| Storage | `Sources/App/Theme/ImportedThemeStore.swift` |
| UI | `Sources/App/Settings/ThemeImportView.swift` |

### Adding Support for Other Formats

Create a new parser in `Sources/Infrastructure/TerminalImport/` that produces a `TerminalColorScheme`. The generator and theme layers work with any source format.

## Theme Properties Reference

### Background

| Property | Type | Description |
|----------|------|-------------|
| `backgroundGradient` | `LinearGradient` | Main app background |
| `showBackgroundOrbs` | `Bool` | Whether to show animated orbs |
| `overlayView` | `AnyView?` | Optional overlay (e.g., snowfall) |

### Cards & Glass

| Property | Type | Description |
|----------|------|-------------|
| `cardGradient` | `LinearGradient` | Card background |
| `glassBackground` | `Color` | Glass effect base |
| `glassBorder` | `Color` | Glass effect border |
| `glassHighlight` | `Color` | Glass top edge shine |
| `cardCornerRadius` | `CGFloat` | Corner radius for cards |
| `pillCornerRadius` | `CGFloat` | Corner radius for pills |

### Typography

| Property | Type | Description |
|----------|------|-------------|
| `textPrimary` | `Color` | Main text color |
| `textSecondary` | `Color` | Subtitle text color |
| `textTertiary` | `Color` | Hint/timestamp color |
| `fontDesign` | `Font.Design` | `.default`, `.rounded`, `.monospaced`, `.serif` |

### Status Colors

| Property | Status | Default Usage |
|----------|--------|---------------|
| `statusHealthy` | >50% remaining | Green |
| `statusWarning` | 20-50% remaining | Yellow/Orange |
| `statusCritical` | <20% remaining | Red |
| `statusDepleted` | 0% remaining | Dark Red/Gray |

### User status color overrides and High Contrast

Users can replace the four status colors without switching themes (Settings → Appearance → Status Colors). Two settings drive it:

| Key | Type | Meaning |
|-----|------|---------|
| `app.statusColorOverrides` | object of `#RRGGBB` per status | The user's own colors; absent statuses defer |
| `app.highContrastEnabled` | Bool | Swap in the built-in appearance-aware palette |

Precedence per status: **user override → High Contrast palette → theme**.

**Where it lives:**
- `Sources/Domain/Settings/StatusColorPolicy.swift` — `RGBColorValue` (sRGB, WCAG contrast math), `StatusPalette.highContrastLight/Dark`, `StatusColorOverrides`, and `StatusColorPolicy.color(for:appearance:)`. SwiftUI-free and unit-tested.
- `Sources/App/Theme/StatusColorOverridingTheme.swift` — a decorator that forwards every `AppThemeProvider` member to the wrapped theme and substitutes the four status colors.
- `ThemeRegistry.resolveTheme(for:systemColorScheme:statusColors:)` — wraps the resolved theme **at resolve time** when the policy is active. Stored themes stay concrete, so `isImported(id:)` and `removeImportedTheme(id:)` keep working.

**Callers must read the policy inside their own observation scope.** `AppThemeProviderModifier` and `NotchRootView` read `AppSettings.shared.statusColorPolicy` in `body`; `StatusItemLabelDriver` carries it (and the current appearance) in `LabelContent` so the menu bar repaints on change.

**Tradeoff:** the decorator does not forward `statusColor(for:)` or `progressGradient(for:)`, so the protocol defaults synthesize them from the overridden colors. A theme with a bespoke `progressGradient` (CLI's flat bar) shows the standard two-stop gradient while overrides or High Contrast are active.

**High Contrast palette** (WCAG ratio against a typical light bar `#ECECEE` / dark bar `#1F1F22`; a Domain test locks every value at ≥ 4.5:1):

| Status | Light appearance | Dark appearance |
|--------|------------------|-----------------|
| healthy | `#17703A` (5.2) | `#00D959` (8.7) |
| warning | `#8A5A00` (5.0) | `#F2BF33` (9.6) |
| critical | `#B81F1F` (5.5) | `#FF5C5C` (5.4) |
| depleted | `#7A1414` (9.2) | `#FF8FA3` (7.6) |

### Accents

| Property | Type | Description |
|----------|------|-------------|
| `accentPrimary` | `Color` | Primary accent color |
| `accentSecondary` | `Color` | Secondary accent color |
| `accentGradient` | `LinearGradient` | Button/highlight gradient |
| `pillGradient` | `LinearGradient` | Provider pill background |
| `shareGradient` | `LinearGradient` | Share button gradient |

## Using BaseTheme

The `BaseTheme` struct provides common color constants:

```swift
public struct BaseTheme {
    // Status colors
    public static let defaultStatusHealthy = Color(...)
    public static let defaultStatusWarning = Color(...)
    public static let defaultStatusCritical = Color(...)
    public static let defaultStatusDepleted = Color(...)

    // Accent colors
    public static let coralAccent = Color(...)
    public static let tealBright = Color(...)
    public static let goldenGlow = Color(...)

    // Purple palette
    public static let purpleDeep = Color(...)
    public static let purpleVibrant = Color(...)
    public static let pinkHot = Color(...)
    public static let magentaSoft = Color(...)
}
```

Use in your theme:

```swift
public var statusHealthy: Color { BaseTheme.defaultStatusHealthy }
public var accentPrimary: Color { BaseTheme.coralAccent }
```

## Migration from Old Theme System

The new theme system coexists with the legacy `AppTheme` static methods. Views can gradually migrate:

### Before (Legacy)
```swift
@Environment(\.colorScheme) var colorScheme
@Environment(\.isChristmasTheme) var isChristmas
@Environment(\.isCLITheme) var isCLI

Text("Hello")
    .foregroundStyle(
        isCLI ? AppTheme.cliTextPrimary
              : isChristmas ? AppTheme.christmasTextPrimary
                            : AppTheme.textPrimary(for: colorScheme)
    )
```

### After (New System)
```swift
@Environment(\.appTheme) var theme

Text("Hello")
    .foregroundStyle(theme.textPrimary)
```

## Design Principles

1. **Protocol-Based**: Same pattern as `ProviderSettingsRepository`
2. **Pluggable**: New themes are single files implementing the protocol
3. **Type-Safe**: Compiler ensures all properties are implemented
4. **Composable**: Themes can share colors via `BaseTheme`
5. **Testable**: Themes can be mocked for UI testing

## File Locations

| Component | Location |
|-----------|----------|
| Protocol | `Sources/App/Theme/AppThemeProvider.swift` |
| Registry | `Sources/App/Theme/ThemeRegistry.swift` |
| Environment | `Sources/App/Theme/ThemeEnvironment.swift` |
| Themes | `Sources/App/Theme/Themes/*.swift` |
| Legacy | `Sources/App/Views/Theme.swift` (will be deprecated) |
