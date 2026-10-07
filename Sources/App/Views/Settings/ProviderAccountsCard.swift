import SwiftUI
import AppKit
import Kit

/// *Accounts* — every login of a provider whose definition can add them:
/// reorder by dragging, pin to the menu bar, rename, pause, remove, and sign
/// in again. Its words are the definition's (`AccountsCardText`).
struct ProviderAccountsCard: View {
    let provider: Provider
    let monitor: QuotaMonitor
    @Environment(\.appTheme) private var theme
    @State private var adding = false
    @State private var renaming: Account?
    @State private var newName = ""
    @State private var removing: Account?
    @State private var reauthMessage: String?

    private var text: AccountsCardText { AccountsCardText(provider: provider) }

    var body: some View {

        let _ = KitObservation.track()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill").foregroundStyle(theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accounts").font(.headline).foregroundStyle(theme.textPrimary)
                    Text(text.count).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                if provider.accounts.hasSeveral {
                    StatusBadge(status: provider.status)
                }
            }

            ForEach(Array(provider.accounts.enumerated()), id: \.element.id) { index, account in
                AccountRow(account: account, inUse: provider.inUse, index: index, text: text, monitor: monitor,
                           onRename: { newName = account.label.isEmpty ? (account.accountEmail ?? "") : account.label; renaming = account },
                           onRemove: { removing = account },
                           onReauth: { reauth(account) })
                    .draggable(account.id)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let moved = provider.accounts.first(where: { $0.id == ids.first }) else { return false }
                        provider.accounts.move(moved, to: index)
                        return true
                    }
            }

            if let inUse = provider.inUse, inUse.offersChoice {
                InUseSettingsSection(inUse: inUse)
            }

            if !text.ways.isEmpty {
                Button { adding = true } label: {
                    Label("Add Account", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.glassBorder, style: StrokeStyle(lineWidth: 1, dash: [4])))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius).fill(theme.cardGradient).themeShadow(theme))
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
        .sheet(isPresented: $adding) {
            AddAccountSheet(provider: provider, monitor: monitor).themedSheet()
        }
        .alert("Rename Account", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let renaming { provider.accounts.rename(account: renaming, name: newName) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A name for this account. Leave it empty to show its email.")
        }
        .confirmationDialog("Remove Account?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { account in
            Button("Remove", role: .destructive) { remove(account) }
        } message: { account in
            Text(text.removeMessage(for: account))
        }
        .alert("Sign In Again", isPresented: Binding(get: { reauthMessage != nil }, set: { if !$0 { reauthMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reauthMessage ?? "")
        }
    }

    private func reauth(_ account: Account) {
        if let help = text.reauthHelp(for: account) {
            reauthMessage = help
            return
        }
        Task {
            do {
                try value(of: await provider.accounts.signInAgain(account: account))
                try await provider.refreshing(account)
            } catch {
                reauthMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ account: Account) {
        provider.accounts.remove(account: account)
        let settings = AppSettings.shared
        let remaining = settings.menuBarProviderIds.filter { $0 != account.id }
        settings.setMenuBarProviderIds(remaining.isEmpty ? [provider.id] : remaining)
        if monitor.selectedProviderId == account.id { monitor.selectedProviderId = provider.id }
    }
}

/// One login: its avatar, name and email, its menu-bar pin, and its actions.
private struct AccountRow: View {
    let account: Account
    /// Its product's *In use* — the terminal's choice, asked about this login.
    let inUse: InUse?
    let index: Int
    let text: AccountsCardText
    let monitor: QuotaMonitor
    let onRename: () -> Void
    let onRemove: () -> Void
    let onReauth: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(NewSessions.self) private var newSessions

    /// The avatar's colour is the page's, by position — not a setting.
    private static let palette: [Color] = [.purple, .orange, .teal, .pink, .blue, .green]

    private var isPinned: Bool { AppSettings.shared.menuBarProviderIds.contains(account.id) }

    var body: some View {

        let _ = KitObservation.track()
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(theme.textTertiary)
                .help("Drag to reorder")
            if let inUse, inUse.canBeInUse(account: account) {
                Button { newSessions.use(account: account) } label: {
                    Image(systemName: inUse.isInUse(account: account) ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(inUse.isInUse(account: account) ? theme.accentPrimary : theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Use for new terminal sessions")
                .accessibilityLabel(inUse.isInUse(account: account) ? "In use for new terminal sessions" : "Use for new terminal sessions")
            }
            Text(String(account.displayName.prefix(1)).uppercased())
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Self.palette[index % Self.palette.count]))
                .opacity(account.isEnabled ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .foregroundStyle(account.isEnabled ? theme.textPrimary : theme.textTertiary)
                if let email = account.accountEmail, email != account.displayName {
                    Text(email).font(.caption).foregroundStyle(theme.textSecondary).textSelection(.enabled)
                } else if account.isDefault {
                    Text(text.defaultLoginDescription).font(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if let left = account.leftPercent {
                Text("\(Int(left))% left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
            }
            if inUse?.isInUse(account: account) == true { InUseBadge() }
            if text.needsReauth(account) {
                Button("Re-auth", action: onReauth)
                    .controlSize(.small)
                    .help("This login needs signing in again.")
            }
            Button { togglePin() } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? theme.accentPrimary : theme.textTertiary)
            .help(isPinned ? "Shown in the menu bar" : "Show in the menu bar")
            Menu {
                Button("Rename…", action: onRename)
                Button(account.isEnabled ? "Pause" : "Resume") { account.isEnabled.toggle() }
                if !account.isDefault {
                    Divider()
                    Button("Remove…", role: .destructive, action: onRemove)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(.rect)
    }

    private func togglePin() {
        let settings = AppSettings.shared
        let ids = settings.menuBarProviderIds
        if isPinned {
            let remaining = ids.filter { $0 != account.id }
            guard !remaining.isEmpty else { return }
            settings.setMenuBarProviderIds(remaining)
        } else {
            settings.setMenuBarProviderIds(ids + [account.id])
        }
    }
}

/// The provider's worst status across its enabled logins.
private struct StatusBadge: View {
    let status: QuotaStatus
    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        Text(status.badgeText)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.statusColor(for: status).opacity(0.2)))
            .foregroundStyle(theme.statusColor(for: status))
    }
}
