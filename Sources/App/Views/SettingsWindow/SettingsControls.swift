import SwiftUI
import Domain
import Infrastructure

// Selection controls shared by the Settings window panes.
// Relocated from the retired inline SettingsView (menu bar popover).

// MARK: - Theme Option Button

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
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(themeProvider.accentGradient)
                        .frame(width: 28, height: 28)

                    Image(systemName: themeProvider.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(themeProvider.id == "cli" ? Color.black : .white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(themeProvider.displayName)
                        .font(.system(size: 11, weight: .medium, design: themeProvider.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    if let subtitle = themeProvider.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(themeProvider.accentPrimary)
                    }
                }

                Spacer()

                if isImported {
                    Button {
                        ThemeRegistry.shared.removeImportedTheme(id: themeProvider.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.statusHealthy)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: themeProvider.cardCornerRadius)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.15) : (isHovering ? theme.hoverOverlay : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: themeProvider.cardCornerRadius)
                            .stroke(isSelected ? theme.accentPrimary : theme.glassBorder.opacity(0.5), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
                    .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
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
                .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
        }
    }
}
