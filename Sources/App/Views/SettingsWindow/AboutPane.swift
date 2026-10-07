import SwiftUI
import Kit

/// About pane: version info and project links.
struct AboutPane: View {
    @Environment(\.appTheme) private var theme

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {

        let _ = KitObservation.track()
        SettingsPane(
            title: "About",
            subtitle: "Version \(appVersion) (\(appBuild))"
        ) {
            VStack(spacing: 14) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 4) {
                    Text("ClaudeBar")
                        .font(theme.font(size: 20, weight: .bold))
                        .foregroundStyle(theme.textPrimary)

                    Text("One menu bar for every AI coding assistant quota.")
                        .font(theme.font(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Link(destination: URL(string: "https://github.com/tddworks/claudebar")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))

                        Text("View on GitHub")
                            .font(theme.font(size: 11, weight: .semibold))

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(theme.accentGradient))
                }
                .buttonStyle(.plain)

                Text("Report issues or contribute on GitHub")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }
}
