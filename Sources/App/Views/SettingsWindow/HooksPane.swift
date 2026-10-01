import SwiftUI
import Domain
import Infrastructure

/// Hooks pane: Claude Code session tracking via the local hook server.
/// Ports the popover hooks card logic: install/uninstall on toggle and a
/// `.hookSettingsChanged` notification so the app starts/stops the server.
struct HooksPane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    @State private var hooksEnabled: Bool = false
    @State private var hooksInstalled: Bool = false
    @State private var hookError: String?

    var body: some View {
        SettingsPane(
            title: "Hooks",
            subtitle: "Let Claude Code push live session events into ClaudeBar."
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Claude Code Hooks",
                    subtitle: "Track Claude Code sessions in real-time. Shows active session status, subagent activity, and task completion."
                ) {
                    Toggle("", isOn: $hooksEnabled)
                        .toggleStyle(.switch)
                        .tint(theme.accentPrimary)
                        .scaleEffect(0.8)
                        .labelsHidden()
                        .onChange(of: hooksEnabled) { _, newValue in
                            applyHooksEnabled(newValue)
                        }
                }

                SettingsRowDivider()

                HStack(spacing: 6) {
                    Circle()
                        .fill(hooksInstalled ? theme.statusHealthy : theme.textTertiary)
                        .frame(width: 6, height: 6)

                    Text(hooksInstalled ? "Hooks installed in ~/.claude/settings.json" : "Hooks not installed")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }

                if let hookError {
                    Text(hookError)
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.statusCritical)
                        .padding(.top, 6)
                }
            }
        }
        .onAppear {
            hooksEnabled = settings.hook.isHookEnabled()
            hooksInstalled = HookInstaller.isInstalled()
        }
    }

    private func applyHooksEnabled(_ newValue: Bool) {
        // Ignore the programmatic sync in onAppear.
        guard newValue != settings.hook.isHookEnabled() else { return }
        hookError = nil
        do {
            if newValue {
                try HookInstaller.install()
            } else {
                try HookInstaller.uninstall()
            }
            settings.hook.setHookEnabled(newValue)
            hooksInstalled = HookInstaller.isInstalled()
            NotificationCenter.default.post(
                name: .hookSettingsChanged,
                object: nil,
                userInfo: ["enabled": newValue]
            )
        } catch {
            hookError = error.localizedDescription
            hooksEnabled = !newValue
            AppLog.hooks.error("Hook \(newValue ? "install" : "uninstall") failed: \(error.localizedDescription)")
        }
    }
}
