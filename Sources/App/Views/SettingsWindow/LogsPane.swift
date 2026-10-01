import SwiftUI
import Domain
import Infrastructure

/// Logs pane: quick access to the file log.
struct LogsPane: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        SettingsPane(
            title: "Logs",
            subtitle: "~/Library/Logs/ClaudeBar/ClaudeBar.log · rotates at 5 MB"
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Application Log",
                    subtitle: "Opens ClaudeBar.log in TextEdit. Attach it when reporting issues."
                ) {
                    Button {
                        FileLogger.shared.openCurrentLogFile()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11, weight: .semibold))

                            Text("Open Log File")
                                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(theme.accentGradient))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
