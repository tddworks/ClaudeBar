import SwiftUI

/// Shared layout primitives for Settings window panes: pane scaffold,
/// glass cards, and title/description rows — all themed via AppThemeProvider.

/// Scrollable pane scaffold with a large title and subtitle.
struct SettingsPane<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 21, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
                .padding(.bottom, 8)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
    }
}

/// Glass card container matching the app's card language.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// A settings row: title + optional description on the left, a trailing
/// control on the right. Stack multiple rows inside a SettingsCard with
/// SettingsRowDivider between them.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
    }
}

/// Divider between rows inside a SettingsCard.
struct SettingsRowDivider: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Divider()
            .background(theme.glassBorder.opacity(0.5))
            .padding(.vertical, 12)
    }
}

/// Standard switch toggle used across the Settings window.
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .tint(theme.accentPrimary)
            .scaleEffect(0.8)
            .labelsHidden()
    }
}

/// Small uppercase field label (e.g. "PROVIDER", "QUOTA").
struct SettingsFieldLabel: View {
    let text: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(theme.textSecondary)
            .tracking(0.5)
    }
}

/// Themed segmented control matching the design's `.segment` language:
/// an inset track with pill buttons, the selected one lifted with a glass
/// fill. Replaces stock AppKit pickers, which ignore the app theme.
struct SettingsSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                SegmentButton(
                    title: label(option),
                    isSelected: selection == option
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: theme.fontDesign))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? AnyShapeStyle(theme.glassBackground) : (isHovering ? AnyShapeStyle(theme.hoverOverlay) : AnyShapeStyle(Color.clear)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isSelected ? theme.glassHighlight.opacity(0.5) : Color.clear, lineWidth: 1)
                        )
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
