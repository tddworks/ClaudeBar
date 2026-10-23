import SwiftUI
import AppKit
import Domain
import Infrastructure

/// Local API pane: the one switch for the localhost-only read-only API and
/// MCP server, and the lines to copy while it is on — the `claude mcp add`
/// command and two curls. The toggle saves `api.enabled` and posts
/// `.localAPISettingsChanged`, so the app starts/stops the server the same
/// way it does the hook server's.
struct LocalAPIPane: View {
    @Environment(\.appTheme) private var theme
    @State private var settings = AppSettings.shared

    @State private var apiEnabled: Bool = false
    /// The port the server answers on — the port file's word (the server
    /// wrote the real number there), or the default before it ever ran.
    @State private var port: Int = Int(LocalAPIServer.defaultPort)

    var body: some View {
        SettingsPane(
            title: "Local API",
            subtitle: "Answer quota questions on this Mac, read-only, for agents and launchers."
        ) {
            SettingsCard {
                SettingsRow(
                    title: "Local API & MCP",
                    subtitle: "Serves your quota status on 127.0.0.1 only — nothing leaves this Mac, and nothing can be changed through it."
                ) {
                    SettingsSwitch(isOn: $apiEnabled)
                        .accessibilityLabel("Local API and MCP")
                        .onChange(of: apiEnabled) { _, newValue in
                            applyAPIEnabled(newValue)
                        }
                }

                if apiEnabled {
                    SettingsRowDivider()

                    copyRow(
                        title: "Add to Claude Code",
                        line: "claude mcp add --transport http claudebar \(baseURL)/mcp"
                    )

                    SettingsRowDivider()

                    copyRow(
                        title: "Ask from a terminal",
                        line: "curl \(baseURL)/status"
                    )

                    SettingsRowDivider()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(theme.statusHealthy)
                            .frame(width: 6, height: 6)

                        Text("Listening on 127.0.0.1:\(port) — routes: /status · /providers · /forecast · /usage/days · /mcp")
                            .font(theme.font(size: 11, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .onAppear {
            apiEnabled = settings.localAPI.isLocalAPIEnabled()
            port = PortFile.localAPI.read() ?? Int(LocalAPIServer.defaultPort)
        }
        .onReceive(NotificationCenter.default.publisher(for: .localAPIPortChanged).receive(on: DispatchQueue.main)) { _ in
            // The server says its socket is ready — the file now names the
            // port that actually answers, default or moved.
            port = PortFile.localAPI.read() ?? port
        }
    }

    private var baseURL: String {
        "http://127.0.0.1:\(port)"
    }

    /// One line to copy: the line itself in selectable text, a copy button
    /// beside it.
    private func copyRow(title: String, line: String) -> some View {
        SettingsRow(
            title: title,
            subtitle: line
        ) {
            SettingsActionButton(title: "Copy", iconName: "doc.on.doc", style: .secondary) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line, forType: .string)
            }
            .accessibilityLabel("Copy \(title)")
        }
    }

    private func applyAPIEnabled(_ newValue: Bool) {
        // Ignore the programmatic sync in onAppear.
        guard newValue != settings.localAPI.isLocalAPIEnabled() else { return }
        settings.localAPI.setLocalAPIEnabled(newValue)
        NotificationCenter.default.post(
            name: .localAPISettingsChanged,
            object: nil,
            userInfo: ["enabled": newValue]
        )
    }
}
