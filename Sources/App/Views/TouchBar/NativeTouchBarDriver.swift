import AppKit
import SwiftUI
import Domain
import Infrastructure

// MARK: - Native Touch Bar Driver

/// Manages native macOS NSTouchBar presentation for ClaudeBar when the dropdown or settings window is open.
@MainActor
public final class NativeTouchBarDriver: NSObject, NSTouchBarDelegate {
    public static let shared = NativeTouchBarDriver()

    private var monitor: QuotaMonitor?
    private var currentTouchBar: NSTouchBar?

    public override init() {
        super.init()
    }

    /// Configures the driver with the application's QuotaMonitor instance.
    public func configure(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    /// Creates and returns a fresh native NSTouchBar instance.
    public func makeTouchBar() -> NSTouchBar? {
        guard AppSettings.shared.touchBarEnabled, let _ = monitor else {
            return nil
        }

        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            .touchBarSummary,
            .touchBarProviders,
            .flexibleSpace,
            .touchBarRefresh,
            .touchBarSettings,
        ]
        currentTouchBar = touchBar
        return touchBar
    }

    // MARK: - NSTouchBarDelegate

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard let monitor else { return nil }

        switch identifier {
        case .touchBarSummary:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSHostingView(rootView: TouchBarActiveProviderBadge(monitor: monitor))
            return item

        case .touchBarProviders:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSHostingView(rootView: TouchBarProvidersScrollView(monitor: monitor))
            return item

        case .touchBarRefresh:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh") ?? NSImage(),
                target: self,
                action: #selector(refreshAction)
            )
            button.bezelColor = .controlColor
            item.view = button
            return item

        case .touchBarSettings:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings") ?? NSImage(),
                target: self,
                action: #selector(settingsAction)
            )
            button.bezelColor = .controlColor
            item.view = button
            return item

        default:
            return nil
        }
    }

    @objc private func refreshAction() {
        guard let monitor else { return }
        PersistentTouchBarDriver.shared.triggerRefreshPulse()
        Task {
            await monitor.refreshAll()
        }
    }

    @objc private func settingsAction() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Touch Bar Identifiers

extension NSTouchBarItem.Identifier {
    public static let touchBarSummary = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.summary")
    public static let touchBarProviders = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.providers")
    public static let touchBarRefresh = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.refresh")
    public static let touchBarSettings = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.settings")
}

// MARK: - SwiftUI Touch Bar Views

/// Active provider status badge showing icon, quota %, and health indicator.
public struct TouchBarActiveProviderBadge: View {
    let monitor: QuotaMonitor

    public init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Image(systemName: activeSymbol)
                .font(.system(size: 11, weight: .bold))

            Text(badgeText)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    private var activeSymbol: String {
        ProviderVisualIdentityLookup.symbolIcon(for: monitor.selectedProviderId)
    }

    private var badgeText: String {
        if let selected = monitor.selectedProvider {
            let name = selected.name
            if let lowest = selected.snapshot?.lowestQuota {
                let mode = AppSettings.shared.usageDisplayMode
                let pct = Int(lowest.displayPercent(mode: mode))
                return "\(name) \(pct)%"
            }
            return name
        }
        return "ClaudeBar"
    }

    private var statusColor: Color {
        let status = monitor.selectedProvider?.snapshot?.overallStatus ?? .healthy
        switch status {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .orange
        case .depleted: return .red
        }
    }
}

/// Horizontal list of provider buttons for switching providers directly from the Touch Bar.
public struct TouchBarProvidersScrollView: View {
    let monitor: QuotaMonitor

    public init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(monitor.enabledProviders, id: \.id) { provider in
                    TouchBarProviderItem(
                        provider: provider,
                        isSelected: provider.id == monitor.selectedProviderId
                    ) {
                        monitor.selectedProviderId = provider.id
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: 380)
    }
}

/// Individual provider button on the Touch Bar.
public struct TouchBarProviderItem: View {
    let provider: any AIProvider
    let isSelected: Bool
    let action: () -> Void

    public init(provider: any AIProvider, isSelected: Bool, action: @escaping () -> Void) {
        self.provider = provider
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbolIcon)
                    .font(.system(size: 10, weight: .bold))

                Text(displayText)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.blue.opacity(0.35) : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var symbolIcon: String {
        ProviderVisualIdentityLookup.symbolIcon(for: provider.id)
    }

    private var displayText: String {
        if let lowest = provider.snapshot?.lowestQuota {
            let mode = AppSettings.shared.usageDisplayMode
            let pct = Int(lowest.displayPercent(mode: mode))
            return "\(provider.name) \(pct)%"
        }
        return provider.name
    }
}

/// SwiftUI declarative Touch Bar content.
public struct ClaudeBarNativeTouchBar: View {
    let monitor: QuotaMonitor
    @State private var settings = AppSettings.shared

    public init(monitor: QuotaMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        Group {
            if settings.touchBarEnabled {
                TouchBarActiveProviderBadge(monitor: monitor)

                ForEach(monitor.enabledProviders, id: \.id) { provider in
                    TouchBarProviderItem(
                        provider: provider,
                        isSelected: provider.id == monitor.selectedProviderId
                    ) {
                        monitor.selectedProviderId = provider.id
                    }
                }

                Spacer()

                Button {
                    Task { await monitor.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }
}

// MARK: - Window Accessor for Touch Bar Binding

/// An invisible NSView that binds the window and application's NSTouchBar to NativeTouchBarDriver.
public struct TouchBarWindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> TouchBarAccessoryNSView {
        TouchBarAccessoryNSView()
    }

    public func updateNSView(_ nsView: TouchBarAccessoryNSView, context: Context) {
        nsView.updateTouchBar()
    }
}

public final class TouchBarAccessoryNSView: NSView {
    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTouchBar()
    }

    public func updateTouchBar() {
        guard let window else { return }
        if AppSettings.shared.touchBarEnabled {
            let tb = NativeTouchBarDriver.shared.makeTouchBar()
            window.touchBar = tb
            NSApplication.shared.touchBar = tb
        } else {
            window.touchBar = nil
            NSApplication.shared.touchBar = nil
        }
    }

    override public func makeTouchBar() -> NSTouchBar? {
        guard AppSettings.shared.touchBarEnabled else { return nil }
        return NativeTouchBarDriver.shared.makeTouchBar()
    }
}
