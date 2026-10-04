import SwiftUI

/// The small eye that masks something personal in the popover for screen
/// shares — account emails, your globe country — and shows it again.
/// Remembered across launches by the setting it toggles.
struct PrivacyEyeBadge: View {
    @Binding var isHidden: Bool
    /// What it hides, for the tooltip and VoiceOver: "account emails".
    let what: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button {
            isHidden.toggle()
        } label: {
            Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isHidden ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(isHidden ? theme.progressTrack : Color.clear))
                .overlay(Capsule().stroke(theme.glassBorder, lineWidth: isHidden ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help(isHidden ? "Show \(what)" : "Hide \(what)")
        .accessibilityLabel(isHidden ? "Show \(what)" : "Hide \(what)")
    }
}
