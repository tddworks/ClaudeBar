import Kit
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

        let _ = KitObservation.track()
        Button {
            isHidden.toggle()
        } label: {
            Image(systemName: isHidden ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(isHidden ? theme.textPrimary : theme.textTertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.controlShape.fill(isHidden ? theme.progressTrack : Color.clear))
                .overlay(theme.controlShape.stroke(theme.glassBorder, lineWidth: isHidden ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help(isHidden ? "Show \(what)" : "Hide \(what)")
        .accessibilityLabel(isHidden ? "Show \(what)" : "Hide \(what)")
    }
}
