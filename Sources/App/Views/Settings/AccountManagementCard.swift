import SwiftUI
import Domain

/// Settings card for managing accounts on a multi-account provider.
///
/// Shows the list of configured accounts with options to add, remove,
/// and set the active account. Only rendered for providers that conform
/// to `MultiAccountProvider`.
struct AccountManagementCard: View {
    let provider: any MultiAccountProvider
    @ObservedObject var monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var isExpanded = false
    @State private var showAddSheet = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 8)

            VStack(spacing: 8) {
                ForEach(provider.accounts, id: \.id) { account in
                    accountRow(account)
                }

                addAccountButton
            }
        } label: {
            header
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(theme.accentGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Accounts")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Text("\(provider.accounts.count) account\(provider.accounts.count == 1 ? "" : "s") configured")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()

            // Aggregate status badge
            let statusColor = theme.statusColor(for: provider.aggregateStatus)
            Text(provider.aggregateStatus.badgeText)
                .foregroundColor(statusColor)
        }
    }

    // MARK: - Account Row

    private func accountRow(_ account: ProviderAccount) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        account.accountId == provider.activeAccount.accountId
                            ? theme.accentPrimary
                            : theme.glassBackground
                    )
                    .frame(width: 24, height: 24)

                Text(account.initialLetter)
                    .font(.system(size: 10, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(
                        account.accountId == provider.activeAccount.accountId
                            ? .white
                            : theme.textSecondary
                    )
            }

            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                if let email = account.email {
                    Text(email)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status from snapshot
            if let snapshot = provider.accountSnapshots[account.accountId] {
                let status = snapshot.overallStatus
                Circle()
                    .fill(theme.statusColor(for: status))
                    .frame(width: 8, height: 8)
            }

            // Active indicator
            if account.accountId == provider.activeAccount.accountId {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(theme.statusHealthy)
            } else {
                // Switch button
                Button {
                    provider.switchAccount(to: account.accountId)
                } label: {
                    Text("Switch")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.accentPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .stroke(theme.accentPrimary.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Add Account

    private var addAccountButton: some View {
        Button {
            showAddSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text("Add Account")
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
            }
            .foregroundColor(theme.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.accentPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
        .buttonStyle(.plain)
    }
}
