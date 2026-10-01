import SwiftUI
import Domain
import Infrastructure

/// Root view of the standalone Settings window: a full-height sidebar plus
/// the selected pane, over the theme's background — seamless chrome (the
/// window's title bar is hidden; traffic lights overlay the sidebar top).
struct SettingsWindowView: View {
    let monitor: QuotaMonitor

    /// The one object allowed to write to the linked device. The Notify pane
    /// sends through it rather than opening a second publishing path of its own,
    /// so a button press and the background publish cannot both start a tile.
    let notifyDriver: NotifyPublishDriver

    var onHookSettingsChanged: ((Bool) -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: SettingsSection = .general
    @State private var searchText = ""

    var body: some View {
        ZStack {
            // Real glass: the desktop blurs through the window (Liquid Glass
            // on macOS 26+), with the theme gradient as a translucent tint so
            // the app's identity reads over the blur instead of replacing it.
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
                .ignoresSafeArea()

            theme.backgroundGradient
                .opacity(0.82)
                .ignoresSafeArea()

            if theme.showBackgroundOrbs {
                backgroundOrbs
                    .ignoresSafeArea()
            }

            theme.overlayView

            HStack(spacing: 0) {
                SettingsSidebarView(monitor: monitor, selection: $selection, filter: searchText)
                    .ignoresSafeArea(.container, edges: .top)

                VStack(spacing: 0) {
                    // Search rides the top edge, level with the traffic lights.
                    HStack {
                        Spacer()
                        searchField
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)

                    activePane
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        // Searching narrows the sidebar; keep the selection on a visible
        // section so the pane never shows something the sidebar hides.
        .onChange(of: searchText) { _, newValue in
            let visible = SettingsSection.matching(filter: newValue)
            if !visible.contains(selection), let first = visible.first {
                selection = first
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(TouchBarWindowAccessor())
        .touchBar {
            ClaudeBarNativeTouchBar(monitor: monitor)
        }
        // The hooks toggle posts this from HooksPane; the app's start/stop
        // closure must run even while the menu bar popover is closed.
        .onReceive(NotificationCenter.default.publisher(for: .hookSettingsChanged)) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            onHookSettingsChanged?(enabled)
        }
    }

    @ViewBuilder
    private var activePane: some View {
        switch selection {
        case .general:
            GeneralPane()
        case .appearance:
            AppearancePane()
        case .menuBar:
            MenuBarPane(monitor: monitor)
        case .providers:
            ProvidersPane(monitor: monitor)
        case .syncAlerts:
            SyncAlertsPane()
        case .hooks:
            HooksPane()
        case .notify:
            NotifyPane(monitor: monitor, driver: notifyDriver)
        case .updates:
            UpdatesPane()
        case .logs:
            LogsPane()
        case .about:
            AboutPane()
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)

            TextField("Search settings…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.glassBackground.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.glassBorder, lineWidth: 1)
                )
        )
    }

    /// Soft ambient orbs matching the popover's background treatment.
    private var backgroundOrbs: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.accentSecondary.opacity(colorScheme == .dark ? 0.35 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(x: -120, y: -140)
                    .blur(radius: 60)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.accentPrimary.opacity(colorScheme == .dark ? 0.28 : 0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: geo.size.width - 200, y: geo.size.height - 240)
                    .blur(radius: 60)
            }
        }
    }
}
