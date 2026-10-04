import SwiftUI
import Domain
import Infrastructure

// Selection controls shared by the Settings window panes.
// Relocated from the retired inline SettingsView (menu bar popover).

// MARK: - Theme Option Button

/// A theme as a tile: a small preview drawn from the theme's own paper,
/// card, outline, shadow, accent and number font, its name below. The
/// tile's frame follows the current theme; the preview, the theme it shows.
struct ThemeOptionButton: View {
    let themeProvider: any AppThemeProvider
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var isImported: Bool {
        ThemeRegistry.shared.isImported(id: themeProvider.id)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ThemePreview(themeProvider: themeProvider)
                    .frame(height: 52)

                HStack(spacing: 4) {
                    Text(themeProvider.displayName)
                        .font(.system(size: 11, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let subtitle = themeProvider.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isImported {
                        Button {
                            ThemeRegistry.shared.removeImportedTheme(id: themeProvider.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(themeProvider.displayName)")
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accentPrimary)
                    }
                }
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isHovering && !isSelected ? AnyShapeStyle(theme.hoverOverlay) : AnyShapeStyle(theme.glassBackground))
                    .themeShadow(theme, scale: 0.75)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? theme.accentPrimary : theme.glassBorder,
                            lineWidth: isSelected ? max(2, theme.cardBorderWidth + 0.5) : theme.cardBorderWidth)
            )
            .offset(x: isSelected && theme.cardShadow != nil ? -1 : 0, y: isSelected && theme.cardShadow != nil ? -1 : 0)
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(themeProvider.displayName) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature of a theme: its paper, a card with its outline and shadow,
/// an accent pill, and a number in its own font.
struct ThemePreview: View {
    let themeProvider: any AppThemeProvider

    var body: some View {
        let t = themeProvider
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(t.backgroundGradient)

            RoundedRectangle(cornerRadius: 6)
                .fill(t.cardGradient)
                .themeShadow(t, scale: 0.5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(t.glassBorder, lineWidth: min(t.cardBorderWidth, 2)))
                .frame(height: 17)
                .padding(.horizontal, 7)
                .padding(.top, 7)

            HStack(alignment: .bottom) {
                Capsule()
                    .fill(t.accentGradient)
                    .overlay(Capsule().stroke(t.cardBorderWidth > 1 ? t.glassBorder : .clear, lineWidth: min(t.cardBorderWidth, 2)))
                    .frame(width: 28, height: 10)
                Spacer()
                Text("62%")
                    .font(t.displayFont(size: 11))
                    .foregroundStyle(t.textPrimary)
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(t.glassBorder.opacity(t.cardBorderWidth > 1 ? 1 : 0.6), lineWidth: min(t.cardBorderWidth, 2)))
    }
}

// MARK: - Display Mode Button

struct DisplayModeButton: View {
    let mode: UsageDisplayMode
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var iconName: String {
        switch mode {
        case .remaining: "arrow.down.right"
        case .used: "arrow.up.right"
        case .pace: "gauge.with.needle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))

                Text(mode.displayLabel)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(buttonBackground)
            .foregroundStyle(isSelected ? theme.accentPrimary : theme.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? theme.accentPrimary.opacity(0.2) : (isHovering ? theme.hoverOverlay : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: theme.cardBorderWidth)
            )
    }
}

// MARK: - Menu Bar Choice Buttons

struct MenuBarProviderChoiceButton: View {
    let providerId: String
    let providerName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        MenuBarChoiceButton(
            iconName: ProviderVisualIdentityLookup.symbolIcon(for: providerId),
            label: providerName,
            isSelected: isSelected,
            action: action
        )
    }
}

struct MenuBarQuotaChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        MenuBarChoiceButton(
            iconName: "gauge.with.needle.fill",
            label: title,
            isSelected: isSelected,
            action: action
        )
    }
}

struct MenuBarChoiceButton: View {
    let iconName: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))

                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? selectedForeground : theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var selectedForeground: Color {
        theme.id == "cli" ? theme.textPrimary : .white
    }

    private var buttonBackground: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .fill(theme.accentGradient)
                    .shadow(color: theme.accentPrimary.opacity(0.25), radius: 5, y: 2)
            } else {
                RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                    .fill(isHovering ? theme.hoverOverlay : theme.glassBackground)
            }

            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: theme.cardBorderWidth)
        }
    }
}
