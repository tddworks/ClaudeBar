import AppKit
import SwiftUI
import Domain
import Infrastructure

/// Drives the menu-bar status item imperatively (AppKit), bypassing SwiftUI's
/// `MenuBarExtra` label hosting entirely.
///
/// After system sleep, the MenuBarExtra label hosting view can permanently
/// stop receiving SwiftUI invalidations: the dropdown window keeps updating
/// while the label — and any `.task` attached to it — goes dead until relaunch
/// (issue #192). This driver owns both things that used to live on that label:
///
/// 1. **The pixels** — an `ObservationRenderSync` reads the same observable
///    state the SwiftUI label did (monitor, settings, session) and draws the
///    composed label into `statusItem.button.image`.
/// 2. **The background-refresh lifecycle** — a second sync watches the refresh
///    cadence/target settings and restarts `QuotaMonitor.startMonitoring`,
///    replacing the label's `.task(id:)`.
///
/// Lives for the app's lifetime; the closure retain cycles this creates are
/// intentional and harmless.
@MainActor
final class StatusItemLabelDriver {
    private let monitor: QuotaMonitor
    private let settings: AppSettings
    private let sessionMonitor: SessionMonitor

    private var statusItem: NSStatusItem?
    private var labelSync: ObservationRenderSync<LabelContent>?
    private var loopSync: ObservationRenderSync<RefreshLoopKey>?
    private var streamConsumer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    /// The image currently owned by this driver, and the content it encodes.
    /// Used both to skip redundant redraws (repainting an intact image can
    /// itself flicker) and to recognize external wipes via KVO.
    private var lastImage: NSImage?
    private var lastContent: LabelContent?
    private var imageWipeObservation: NSKeyValueObservation?

    init(monitor: QuotaMonitor, settings: AppSettings, sessionMonitor: SessionMonitor) {
        self.monitor = monitor
        self.settings = settings
        self.sessionMonitor = sessionMonitor
    }

    // No deinit: this object lives for the app's lifetime, so the wake
    // observer is intentionally never removed (and a nonisolated deinit
    // could not touch the @MainActor-isolated observer under Swift 6).

    // MARK: - Label Rendering

    /// Everything the menu-bar pixels depend on. Reading these properties
    /// inside the sync's `read` registers observation for each of them.
    struct LabelContent: Equatable {
        var label: MenuBarLabel?
        var fallbackStatus: QuotaStatus
        var sessionPhase: ClaudeSession.Phase?
        var themeModeId: String
    }

    /// Attaches to the `NSStatusItem` exposed by MenuBarExtraAccess and starts
    /// rendering. Repeated callbacks re-assert the image (cheap, idempotent).
    func attach(_ statusItem: NSStatusItem) {
        guard self.statusItem !== statusItem else {
            labelSync?.renderNow()
            return
        }
        self.statusItem = statusItem
        labelSync?.stop()

        let sync = ObservationRenderSync(
            read: { [self] in currentLabelContent() },
            render: { [self] content in render(content) }
        )
        labelSync = sync
        sync.start()

        // SwiftUI wipes `button.image` whenever the scene re-evaluates (every
        // dropdown open/close flips the `isPresented` binding). Restore it
        // synchronously in the same runloop pass so a blank frame never
        // reaches the screen — repainting from `onAppear`/`onDisappear` alone
        // leaves a visible flash.
        imageWipeObservation?.invalidate()
        imageWipeObservation = statusItem.button?.observe(\.image, options: [.new]) { [weak self] button, change in
            MainActor.assumeIsolated {
                guard let self, let owned = self.lastImage else { return }
                if button.image !== owned {
                    button.image = owned
                }
            }
        }

        if wakeObserver == nil {
            // Belt-and-braces: repaint after wake even if nothing changed,
            // in case the menu bar was rebuilt with stale content.
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.labelSync?.renderNow() }
            }
        }
    }

    /// Defense-in-depth repaint around dropdown open/close (the KVO observer
    /// in `attach` is the primary guard against SwiftUI's image wipes). A
    /// no-op when the image is intact, so it never causes extra redraws.
    func reassertPresentation() {
        labelSync?.renderNow()
    }

    private func currentLabelContent() -> LabelContent {
        LabelContent(
            label: monitor.menuBarLabel(
                providerId: settings.menuBarPercentageProviderId,
                primaryQuotaKey: settings.menuBarPercentageQuotaKey,
                secondaryQuotaKey: settings.menuBarSecondaryQuotaKey,
                showPercentage: settings.menuBarPercentageEnabled,
                showDuration: settings.menuBarDurationEnabled,
                mode: settings.usageDisplayMode,
                burnRateWarningEnabled: settings.burnRateWarningEnabled,
                burnRateThreshold: settings.burnRateThreshold
            ),
            fallbackStatus: effectiveSelectedProviderStatus,
            sessionPhase: sessionMonitor.activeSession?.phase,
            themeModeId: settings.themeMode
        )
    }

    /// Status of the selected provider, considering the burn-rate setting.
    /// Mirrors the dropdown's status logic for the icon-only fallback.
    private var effectiveSelectedProviderStatus: QuotaStatus {
        guard let snapshot = monitor.selectedProvider?.snapshot else { return .healthy }
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    private func render(_ content: LabelContent) {
        guard let button = statusItem?.button else { return }
        // Skip when nothing changed and our image is still in place —
        // re-setting an identical image redraws the button and can flicker.
        if content == lastContent, let lastImage, button.image === lastImage {
            return
        }
        let image = Self.compose(content, theme: resolvedTheme(for: content.themeModeId))
        lastContent = content
        lastImage = image
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = content.label?.text
    }

    private func resolvedTheme(for themeModeId: String) -> any AppThemeProvider {
        let scheme: ColorScheme = NSApp.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        return ThemeRegistry.shared.resolveTheme(for: themeModeId, systemColorScheme: scheme)
    }

    // MARK: - Image Composition

    /// Composes the full status-item image: optional session glyph, then the
    /// usage text — or the themed status icon when no label is configured or
    /// no quota data exists yet. Mirrors the old SwiftUI label exactly.
    static func compose(_ content: LabelContent, theme: any AppThemeProvider) -> NSImage {
        var parts: [NSImage] = []

        if let phase = content.sessionPhase {
            parts.append(symbolImage("terminal.fill", color: NSColor(phase.color)))
        }

        if let label = content.label {
            parts.append(StatusBarPercentageImageRenderer.image(
                text: label.text,
                color: theme.statusColor(for: label.status)
            ))
        } else {
            let symbolName = theme.statusBarIconName ?? fallbackIconName(for: content.fallbackStatus)
            parts.append(symbolImage(
                symbolName,
                color: NSColor(theme.statusColor(for: content.fallbackStatus))
            ))
        }

        return hStack(parts, spacing: 3)
    }

    private static func fallbackIconName(for status: QuotaStatus) -> String {
        switch status {
        case .depleted: "chart.bar.xaxis"
        case .critical: "exclamationmark.triangle.fill"
        case .warning, .healthy: "chart.bar.fill"
        }
    }

    /// Renders an SF Symbol tinted with a fixed color, since the status item
    /// image is non-template (theme colors must survive menu bar appearance).
    private static func symbolImage(_ name: String, color: NSColor) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: .zero)
        }
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    /// Composites images horizontally, vertically centered.
    private static func hStack(_ images: [NSImage], spacing: CGFloat) -> NSImage {
        let images = images.filter { $0.size.width > 0 }
        guard !images.isEmpty else { return NSImage(size: .zero) }

        let width = images.map(\.size.width).reduce(0, +) + spacing * CGFloat(images.count - 1)
        let height = images.map(\.size.height).max() ?? 0
        let composed = NSImage(size: NSSize(width: ceil(width), height: ceil(height)), flipped: false) { _ in
            var x: CGFloat = 0
            for image in images {
                image.draw(at: NSPoint(x: x, y: (height - image.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
                x += image.size.width + spacing
            }
            return true
        }
        composed.isTemplate = false
        return composed
    }

    // MARK: - Background Refresh Lifecycle

    /// Identity for the background-refresh loop — replaces the `.task(id:)`
    /// that lived on the (freeze-prone) SwiftUI label.
    struct RefreshLoopKey: Equatable {
        var isEnabled: Bool
        var seconds: Int
        var providerIds: [String]?
    }

    /// Starts watching the refresh cadence/target settings and (re)starts the
    /// monitoring loop whenever they change. Call once at app startup.
    func startMonitoringLifecycle() {
        guard loopSync == nil else { return }
        let sync = ObservationRenderSync(
            read: { [self] in currentRefreshLoopKey() },
            render: { [self] key in restartMonitoring(key) }
        )
        loopSync = sync
        sync.start()
    }

    private func currentRefreshLoopKey() -> RefreshLoopKey {
        let interval = settings.refreshInterval
        return RefreshLoopKey(
            isEnabled: interval.isEnabled,
            seconds: interval.seconds ?? 0,
            providerIds: backgroundRefreshProviderIds
        )
    }

    /// While the dropdown is closed we only need the menu-bar provider(s)
    /// fresh, so narrow the periodic refresh to the selected + configured
    /// menu-bar provider when a menu-bar readout is on; otherwise just the
    /// selected provider. Disabled providers are dropped (issue #67).
    private var backgroundRefreshProviderIds: [String]? {
        guard settings.menuBarPercentageEnabled || settings.menuBarDurationEnabled else { return nil }
        let enabledProviderIds = Set(monitor.enabledProviders.map(\.id))
        return [
            monitor.selectedProviderId,
            settings.menuBarPercentageProviderId,
        ].filter { enabledProviderIds.contains($0) }
    }

    private func restartMonitoring(_ key: RefreshLoopKey) {
        streamConsumer?.cancel()
        streamConsumer = nil
        guard key.isEnabled else {
            monitor.stopMonitoring()
            return
        }
        AppLog.monitor.info("Background refresh starting (interval: \(key.seconds)s, providers: \(key.providerIds?.joined(separator: ",") ?? "selected"))")
        let stream = monitor.startMonitoring(
            interval: .seconds(key.seconds),
            providerIds: key.providerIds
        )
        streamConsumer = Task {
            // QuotaMonitor updates provider snapshots; the label sync re-renders
            // from observable state — nothing to do per event.
            for await _ in stream {}
        }
    }
}

/// Renders status text as an original-color image because macOS can ignore
/// `Text.foregroundStyle` inside a menu bar item.
enum StatusBarPercentageImageRenderer {
    @MainActor
    static func image(text: String, color: Color) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(color),
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        let imageSize = NSSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let image = NSImage(size: imageSize, flipped: false) { _ in
            attributedText.draw(at: .zero)
            return true
        }
        image.isTemplate = false

        return image
    }
}
