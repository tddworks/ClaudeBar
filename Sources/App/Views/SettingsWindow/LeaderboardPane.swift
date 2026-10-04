import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Domain
import Infrastructure

/// *SETTINGS → LEADERBOARD*: your name, whether you're shown, what you share,
/// your own data, and leaving. Joining is here or in the popover's tab.
struct LeaderboardPane: View {
    let leaderboard: Leaderboard
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var newName = ""
    @State private var message: String?
    @State private var confirmLeave = false
    @State private var isWorking = false

    private var membership: LeaderboardMembership { leaderboard.membership }

    var body: some View {
        SettingsPane(
            title: "Leaderboard",
            subtitle: "Share daily token totals from the providers you choose and see where you rank. Only token counts leave this Mac, signed by a key that never does."
        ) {
            if membership.isJoined {
                accountCard
                sharingCard
                dataCard
            } else {
                // Joinable here too: Overview mode hides the popover's tabs.
                LeaderboardJoinView(leaderboard: leaderboard, monitor: monitor)
                    .frame(maxWidth: 520, alignment: .leading)
            }
            if let message {
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private var accountCard: some View {
        SettingsCard {
            SettingsRow(title: "Username", subtitle: membership.username?.description) {
                HStack(spacing: 6) {
                    SettingsTextField(placeholder: "new-name", text: $newName)
                        .frame(width: 140)
                    SettingsActionButton(title: "Rename", iconName: "pencil", style: .secondary) {
                        run { try await membership.rename(to: Username(newName)!); newName = "" }
                    }
                    .disabled(Username(newName) == nil || isWorking)
                }
            }
            SettingsRowDivider()
            SettingsRow(title: "Show me on the web board",
                        subtitle: "Off keeps you ranked only in your own ClaudeBar.") {
                SettingsSwitch(isOn: Binding(
                    get: { membership.isVisible },
                    set: { visible in run { try await membership.setVisible(visible) } }
                ))
            }
        }
    }

    private var sharingCard: some View {
        SettingsCard {
            SettingsFieldLabel(text: "SHARED PROVIDERS").padding(.bottom, 6)
            ForEach(Array(membership.shareableProviders.sorted().enumerated()), id: \.element) { index, id in
                if index > 0 { SettingsRowDivider() }
                SettingsRow(title: leaderboardProviderName(id, in: monitor), subtitle: "Daily token totals from its logs") {
                    SettingsSwitch(isOn: Binding(
                        get: { membership.sharing.contains(id) },
                        set: { on in
                            if on { try? membership.share(id) } else { membership.stopSharing(id) }
                            Task { await leaderboard.uploader.uploadDue() }
                        }
                    ))
                }
            }
            Text("Turning a provider off stops new uploads for it; days already uploaded stay until you leave.")
                .font(.system(size: 11, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 8)
        }
    }

    private var dataCard: some View {
        SettingsCard {
            SettingsRow(title: "Export my data", subtitle: "Everything the server holds about you, as JSON.") {
                SettingsActionButton(title: "Export…", iconName: "square.and.arrow.down", style: .secondary) {
                    run { try await export() }
                }
                .disabled(isWorking)
            }
            SettingsRowDivider()
            SettingsRow(title: "Leave and delete my data",
                        subtitle: "Removes your username and every uploaded day from the server, then this Mac's key.") {
                SettingsActionButton(title: "Leave…", iconName: "rectangle.portrait.and.arrow.right", style: .destructive) {
                    confirmLeave = true
                }
                .disabled(isWorking)
            }
            .confirmationDialog("Leave the leaderboard?", isPresented: $confirmLeave) {
                Button("Leave and delete my data", role: .destructive) {
                    run { try await membership.leave(); message = "You left the leaderboard. Your data was deleted." }
                }
            } message: {
                Text("Your username and every uploaded day are deleted from the server. This can't be undone.")
            }
        }
    }

    private func export() async throws {
        let summary = try await membership.myStanding(in: BoardView(period: .thirtyDays))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(summary)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "claudebar-leaderboard-\(membership.username?.value ?? "me").json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url)
        message = "Saved to \(url.lastPathComponent)."
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                message = (error as? LeaderboardError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
