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
                        .font(theme.displayFont(size: theme.displayFontName == nil ? 21 : 26))
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
                .fill(theme.cardGradient).themeShadow(theme)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
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
        if theme.isOutlined {
            // Printed rows part with a dashed rule, as on paper.
            Line()
                .stroke(theme.progressTrack, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(height: 2)
                .padding(.vertical, 12)
        } else {
            Divider()
                .background(theme.glassBorder.opacity(0.5))
                .padding(.vertical, 12)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// Standard switch toggle used across the Settings window.
struct SettingsSwitch: View {
    @Binding var isOn: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        if theme.isOutlined {
            // An outlined theme's switch: an inked capsule, healthy when on.
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? theme.statusHealthy : theme.progressTrack)
                        .overlay(Capsule().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth * 0.8))
                    Circle()
                        .fill(theme.glassBackground)
                        .overlay(Circle().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth * 0.8))
                        .padding(3)
                }
                .frame(width: 40, height: 23)
            }
            .buttonStyle(.plain)
            .accessibilityRepresentation { Toggle("", isOn: $isOn) }
        } else {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(theme.accentPrimary)
                .scaleEffect(0.8)
                .labelsHidden()
        }
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
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
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

/// A settings action: a capsule in the theme's accent, a quiet glass one, or
/// a destructive one in the critical status colour.
struct SettingsActionButton: View {
    enum Style { case prominent, secondary, destructive }

    let title: String
    let iconName: String
    var style: Style = .prominent
    var isBusy: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    init(title: String, iconName: String, style: Style = .prominent, isBusy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.iconName = iconName
        self.style = style
        self.isBusy = isBusy
        self.action = action
    }

    /// Notify!'s spelling: prominent or not.
    init(title: String, iconName: String, isProminent: Bool, isBusy: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, iconName: iconName, style: isProminent ? .prominent : .secondary, isBusy: isBusy, action: action)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
            }
            .foregroundStyle(style == .secondary ? theme.textPrimary : theme.textOnStatus)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(background)
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        ZStack {
            switch style {
            case .prominent: Capsule().fill(theme.accentGradient)
            case .secondary: Capsule().fill(theme.glassBackground)
            case .destructive: Capsule().fill(theme.statusCritical)
            }
            Capsule().stroke(style == .prominent ? Color.clear : theme.glassBorder, lineWidth: theme.cardBorderWidth)
        }
    }
}

/// A text field in the settings' field style.
struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.textTertiary))
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.glassBackground)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
    }
}
