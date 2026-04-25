import SwiftUI
import Domain

/// A compact horizontal account picker for multi-account providers.
///
/// Shown in the provider section header when a provider conforms to
/// `MultiAccountProvider` and has more than one account. Renders as
/// a row of small pills, similar to the existing provider pills.
///
/// Single-account providers never show this view — backward compatible.
struct AccountPickerView: View {
    let provider: any MultiAccountProvider
    let onSwitch: (String) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(provider.accounts, id: \.id) { account in
                    AccountPill(
                        account: account,
                        isActive: account.accountId == provider.activeAccount.accountId
                    ) {
                        onSwitch(account.accountId)
                    }
                }
            }
        }
    }
}

/// A single account pill in the picker.
struct AccountPill: View {
    let account: ProviderAccount
    let isActive: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Avatar circle with initial letter
                ZStack {
                    Circle()
                        .fill(isActive ? theme.accentPrimary : theme.glassBackground)
                        .frame(width: 16, height: 16)

                    Text(account.initialLetter)
                        .font(.system(size: 8, weight: .bold, design: theme.fontDesign))
                        .foregroundColor(isActive ? .white : theme.textSecondary)
                }

                Text(account.displayName)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium, design: theme.fontDesign))
                    .foregroundColor(isActive ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive ? theme.accentPrimary.opacity(0.15) : (isHovering ? theme.hoverOverlay : Color.clear))
                    .overlay(
                        Capsule()
                            .stroke(isActive ? theme.accentPrimary.opacity(0.5) : theme.glassBorder.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
