import SwiftUI
import Domain

/// The login the popover is showing: its initial, its email or organization
/// — masked when *Hide account email* is on (#375) — its plan badge, the eye
/// that hides or shows emails, and how fresh its numbers are.
struct AccountCardView: View {
    let providerId: String
    let displayName: String
    let snapshot: UsageSnapshot
    let freshness: String

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State var settings = AppSettings.shared

    var body: some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(ProviderVisualIdentityLookup.gradient(for: providerId, scheme: colorScheme))
                    .frame(width: 32, height: 32)

                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(settings.shown(displayName))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    // Account tier badge
                    if let accountTier = snapshot.accountTier {
                        Text(accountTier.badgeText)
                            .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.accentPrimary.opacity(0.8))
                            )
                    }

                    // Hide account email (#375): mask it here and in the menu bar.
                    if displayName.contains("@") {
                        emailMaskBadge
                    }
                }

                Text(freshness)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // Stale indicator
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.statusWarning)
            }
        }
        .padding(10)
        .themeCard()
    }

    /// The eye after the account: masks every account email in the popover
    /// and the menu bar, or shows them again — remembered across launches.
    private var emailMaskBadge: some View {
        PrivacyEyeBadge(isHidden: $settings.hideAccountEmail, what: "account emails")
    }
}
