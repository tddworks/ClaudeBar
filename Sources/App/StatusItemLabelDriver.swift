import AppKit
import CoreText
import SwiftUI
import Domain
import Infrastructure
import Providers

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
    private var blinkSync: ObservationRenderSync<Bool>?
    private var streamConsumer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var appearanceObserver: NSKeyValueObservation?

    /// Polls for a status item we can actually draw into. See
    /// `startAttachLifecycle` for why MenuBarExtraAccess alone isn't enough.
    private var attachWatchdog: Task<Void, Never>?

    /// One-shot latch so a missing button is logged once, not twice a second.
    private var hasLoggedMissingButton = false

    /// Drives the countdown: every tick re-reads the label (picking up the
    /// current wall clock) and flips `blinkPhase`. See `startBlinkTimer`.
    private var blinkTimer: Timer?
    private var blinkPhase = true

    /// The image currently owned by this driver, and the content it encodes.
    /// Used both to skip redundant redraws (repainting an intact image can
    /// itself flicker) and to recognize external wipes via KVO.
    private var lastImage: NSImage?
    private var lastContent: LabelContent?
    private var lastLabelSelection: [String]?
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
        var additionalLabels: [MenuBarProviderLabel] = []
        var primaryProviderId: String? = nil
        var primaryProviderName: String? = nil
        /// Short account names by lineup id, for providers with several
        /// enabled logins — `MenuBarAccountName`.
        var accountNames: [String: String] = [:]
        var fallbackStatus: QuotaStatus
        var sessionPhase: ClaudeSession.Phase?
        var themeModeId: String
        /// Whether a dual-window label should render as two stacked smaller
        /// lines instead of one long "A | B" line (opt-in setting).
        var stacked: Bool = false
        /// The user-selected text size for the stacked lines. Carried in the
        /// content (not read at draw time) so changing the size in Settings
        /// invalidates the observation sync and repaints the label.
        var stackedSize: MenuBarStackedSize = .default
        /// Carried like `stackedSize` so a Settings change repaints.
        var statusColors: StatusColorPolicy = .default
        /// The High Contrast palette is per-appearance and `render` skips
        /// identical content, so an appearance flip must change the content.
        var isDarkAppearance: Bool = true
        /// Global Appearance preference, included so toggling repaints immediately.
        var nativeMenuBarIconsEnabled: Bool = false
        /// Blink phase for an H:MM countdown's separator colon. Only alternates
        /// while the label actually holds a countdown colon, so a "2d" or "45m"
        /// label keeps comparing equal across ticks and never repaints for the
        /// blink alone (see `render`'s early-out).
        var colonVisible: Bool = true
    }

    /// Attaches to an `NSStatusItem` and starts rendering. Repeated callbacks
    /// re-assert the image (cheap, idempotent).
    ///
    /// Rejects an item with no `button`, because every render into it would
    /// silently no-op and the menu bar would show nothing but the 1x1
    /// placeholder label — an invisible, unfindable status item with no route
    /// to Settings (issue #258).
    ///
    /// That is reachable through MenuBarExtraAccess, which hands over
    /// `statusItems[0]`. With "Displays have Separate Spaces" there is one
    /// `NSStatusBarWindow` per screen — the real item plus one replicant per
    /// additional display — and only the real one carries a button. Before
    /// macOS 26 the replicant was a distinct class the library filtered out;
    /// on macOS 26 both report `NSSceneStatusItem`, so its filter keeps both
    /// and which one lands at index 0 is left to `NSApp.windows` ordering.
    func attach(_ statusItem: NSStatusItem) {
        guard statusItem.button != nil else {
            AppLog.ui.warning("Status item has no button (per-display replicant); looking for the real one")
            startAttachWatchdog()
            return
        }
        guard self.statusItem !== statusItem else {
            labelSync?.renderNow()
            return
        }
        attachWatchdog?.cancel()
        attachWatchdog = nil
        hasLoggedMissingButton = false
        self.statusItem = statusItem
        labelSync?.stop()

        let sync = ObservationRenderSync(
            read: { [self] in currentLabelContent() },
            render: { [self] content in render(content) }
        )
        labelSync = sync
        sync.start()
        startBlinkLifecycle()

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

        // Nothing observable feeds `LabelContent.isDarkAppearance`; the
        // button's appearance flips on a system change and, on macOS 26,
        // when the wallpaper behind the bar changes brightness.
        appearanceObserver?.invalidate()
        appearanceObserver = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.labelSync?.renderNow() }
        }
    }

    /// Defense-in-depth repaint around dropdown open/close (the KVO observer
    /// in `attach` is the primary guard against SwiftUI's image wipes). A
    /// no-op when the image is intact, so it never causes extra redraws.
    func reassertPresentation() {
        labelSync?.renderNow()
    }

    private func currentLabelContent() -> LabelContent {
        let primaryQuotaKey = settings.menuBarPercentageQuotaKey.isEmpty
            ? (monitor.provider(for: settings.menuBarPercentageProviderId).flatMap { monitor.usage(of: $0) }?.quotas.first?.quotaType.quotaKey ?? "session")
            : settings.menuBarPercentageQuotaKey
        let freshLabel = monitor.menuBarLabel(
            providerId: settings.menuBarPercentageProviderId,
            primaryQuotaKey: primaryQuotaKey,
            secondaryQuotaKey: settings.menuBarSecondaryQuotaKey,
            showPercentage: settings.menuBarPercentageEnabled,
            showDuration: settings.menuBarDurationEnabled,
            mode: settings.usageDisplayMode,
            burnRateWarningEnabled: settings.burnRateWarningEnabled,
            burnRateThreshold: settings.burnRateThreshold
        )

        let selection = [settings.menuBarPercentageProviderId,
                         settings.menuBarPercentageQuotaKey, settings.menuBarSecondaryQuotaKey,
                         String(settings.menuBarPercentageEnabled), String(settings.menuBarDurationEnabled),
                         settings.usageDisplayMode.rawValue]
        let label = freshLabel ?? (lastLabelSelection == selection
            ? lastKnownLabel(whenFreshIsMissing: freshLabel) : nil)
        lastLabelSelection = selection
        let additionalLabels = monitor.additionalMenuBarLabels(
            providerIds: settings.menuBarAdditionalProviderIds,
            configurations: settings.menuBarProviderSettings,
            showPercentage: settings.menuBarPercentageEnabled,
            showDuration: settings.menuBarDurationEnabled,
            mode: settings.usageDisplayMode,
            burnRateWarningEnabled: settings.burnRateWarningEnabled,
            burnRateThreshold: settings.burnRateThreshold
        )
        let hasCountdownColon = ([label].compactMap { $0 } + additionalLabels.map(\.label))
            .contains { !CountdownColon.ranges(in: $0.text).isEmpty }
        let primaryProvider = monitor.enabledProviders.first { $0.id == settings.menuBarPercentageProviderId }
        let showsQuota = settings.menuBarPercentageEnabled || settings.menuBarDurationEnabled
        let shownIds = [settings.menuBarPercentageProviderId] + additionalLabels.map(\.providerId)
        let accountNames = MenuBarAccountName.names(Dictionary(uniqueKeysWithValues: Set(shownIds).compactMap { id in
            (monitor.enabledProviders.first { $0.id == id } as? Account)
                .flatMap { $0.provider.hasSeveralAccounts ? (id, settings.shown($0.displayName)) : nil }
        }))
        let primaryProviderName = Self.showsPrimaryLogo(
            showsQuota: showsQuota,
            hasOtherReadouts: !additionalLabels.isEmpty,
            hasAccountName: accountNames[settings.menuBarPercentageProviderId] != nil,
            logoAlways: settings.menuBarProviderLogoEnabled
        ) ? primaryProvider.map { settings.shown($0.name) } : nil

        return LabelContent(
            label: label,
            additionalLabels: additionalLabels,
            primaryProviderId: primaryProviderName == nil ? nil : settings.menuBarPercentageProviderId,
            primaryProviderName: primaryProviderName,
            // Hidden labels still keep the icon: the full names decide that above.
            accountNames: settings.menuBarAccountLabelsEnabled ? accountNames : [:],
            fallbackStatus: effectiveSelectedProviderStatus,
            sessionPhase: sessionMonitor.activeSession?.phase,
            themeModeId: settings.themeMode,
            stacked: settings.menuBarStackedEnabled,
            stackedSize: settings.menuBarStackedSize,
            statusColors: settings.statusColorPolicy,
            isDarkAppearance: isDarkAppearance,
            nativeMenuBarIconsEnabled: settings.nativeMenuBarIconsEnabled,
            colonVisible: hasCountdownColon ? blinkPhase : true
        )
    }

    /// Read from the button, not `NSApp`: on macOS 26 the bar is transparent
    /// and picks light or dark ink from the wallpaper behind it, independent
    /// of the system appearance setting.
    private var isDarkAppearance: Bool {
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Bridges a momentarily-missing menu-bar label. The configured quota window
    /// can briefly vanish from a snapshot (cold start before the first success, a
    /// parse gap), which would otherwise collapse the menu bar to a lone icon. As
    /// long as the menu-bar provider is enabled and still holds a snapshot, keep
    /// the last value we showed instead of blanking the number. Returns nil when
    /// we have nothing to fall back to, so the normal "no data yet" icon shows.
    private func lastKnownLabel(whenFreshIsMissing freshLabel: MenuBarLabel?) -> MenuBarLabel? {
        guard freshLabel == nil, let previous = lastContent?.label else { return nil }
        let providerHasSnapshot = monitor.enabledProviders.contains {
            $0.id == settings.menuBarPercentageProviderId && $0.snapshot != nil
        }
        return providerHasSnapshot ? previous : nil
    }

    /// Status of the selected provider, considering the burn-rate setting.
    /// Mirrors the dropdown's status logic for the icon-only fallback.
    private var effectiveSelectedProviderStatus: QuotaStatus {
        monitor.selectedProvider.flatMap { monitor.usage(of: $0) }?.overallStatus(under: settings.statusPolicy) ?? .healthy
    }

    private func render(_ content: LabelContent) {
        guard let button = statusItem?.button else {
            // Loud but once: the symptom is a menu bar item that is invisible
            // and unclickable, which otherwise leaves no trace in the log.
            if !hasLoggedMissingButton {
                hasLoggedMissingButton = true
                AppLog.ui.error("Status item has no button — nothing can be drawn into the menu bar")
            }
            return
        }
        // Skip when nothing changed and our image is still in place —
        // re-setting an identical image redraws the button and can flicker.
        if content == lastContent, let lastImage, button.image === lastImage {
            return
        }
        let image = Self.compose(content, theme: resolvedTheme(for: content))
        lastContent = content
        lastImage = image
        button.image = image
        button.imagePosition = .imageOnly
        let primaryText = [content.primaryProviderName, content.label?.text].compactMap { $0 }.joined(separator: " ")
        let tooltip = settings.shown(([primaryText].filter { !$0.isEmpty } + content.additionalLabels.map(\.text))
            .joined(separator: " | "))
        button.toolTip = tooltip.isEmpty ? nil : tooltip
        button.setAccessibilityLabel(tooltip.isEmpty ? "ClaudeBar" : tooltip)
    }

    private func resolvedTheme(for content: LabelContent) -> any AppThemeProvider {
        ThemeRegistry.shared.resolveTheme(
            for: content.themeModeId,
            systemColorScheme: content.isDarkAppearance ? .dark : .light,
            statusColors: content.statusColors
        )
    }

    /// Whether the primary readout starts with its provider's logo: when
    /// there are readouts to tell apart — another provider, or an account
    /// name — or when the person asked for it always. Never without a readout.
    static func showsPrimaryLogo(showsQuota: Bool, hasOtherReadouts: Bool, hasAccountName: Bool, logoAlways: Bool) -> Bool {
        showsQuota && (hasOtherReadouts || hasAccountName || logoAlways)
    }

    // MARK: - Image Composition

    /// Composes the full status-item image: optional session glyph, then the
    /// usage text — or the themed status icon when no label is configured or
    /// no quota data exists yet. Mirrors the old SwiftUI label exactly.
    static func compose(_ content: LabelContent, theme: any AppThemeProvider) -> NSImage {
        var parts: [NSImage] = []

        // Only surface the session glyph while Claude is actively working. A
        // finished/idle (.stopped) or .ended session must not leave a lone
        // orange glyph sitting in the menu bar — that reads as a frozen crash
        // (the user's report) since `Stop` fires at the end of every turn.
        var showsSessionGlyph = false
        if let phase = content.sessionPhase, phase == .active || phase == .subagentsWorking {
            let color = sessionGlyphColor(
                phase: phase, theme: theme, status: content.fallbackStatus,
                showsUsageText: content.label != nil, darkMenuBar: content.isDarkAppearance
            )
            parts.append(symbolImage(sessionGlyphSymbol, color: NSColor(color)))
            showsSessionGlyph = true
        }

        if let providerId = content.primaryProviderId {
            parts.append(providerIcon(for: providerId, native: content.nativeMenuBarIconsEnabled, dark: content.isDarkAppearance))
        }

        if let id = content.primaryProviderId, let name = content.accountNames[id] {
            parts.append(StatusBarPercentageImageRenderer.image(text: name, color: .primary))
        }

        if let label = content.label {
            parts.append(quotaImage(label, stacked: content.stacked, size: content.stackedSize,
                                    colonVisible: content.colonVisible, theme: theme, dark: content.isDarkAppearance))
        } else {
            if let symbolName = statusIconSymbol(
                theme: theme, status: content.fallbackStatus, besideSessionGlyph: showsSessionGlyph
            ) {
                parts.append(symbolImage(
                    symbolName,
                    color: NSColor(theme.menuBarStatusColor(for: content.fallbackStatus, darkMenuBar: content.isDarkAppearance))
                ))
            }
        }

        for label in content.additionalLabels {
            // Chips stand apart on their own; text needs a separator.
            if !theme.isOutlined || label.stacked {
                parts.append(StatusBarPercentageImageRenderer.image(
                    text: " | ", color: theme.menuBarStatusColor(for: label.status, darkMenuBar: content.isDarkAppearance)
                ))
            }
            parts.append(providerIcon(for: label.providerId, native: content.nativeMenuBarIconsEnabled, dark: content.isDarkAppearance))
            if let name = content.accountNames[label.providerId] {
                parts.append(StatusBarPercentageImageRenderer.image(text: name, color: .primary))
            }
            parts.append(quotaImage(label.label, stacked: label.stacked, size: label.stackedSize,
                                    colonVisible: content.colonVisible, theme: theme, dark: content.isDarkAppearance))
        }
        return hStack(parts, spacing: 3)
    }

    private static func quotaImage(_ label: MenuBarLabel, stacked: Bool, size: MenuBarStackedSize,
                                   colonVisible: Bool, theme: any AppThemeProvider, dark: Bool) -> NSImage {
        if stacked, label.segments.count == 2 {
            return StatusBarStackedImageRenderer.image(
                top: (label.segments[0].text, theme.menuBarStatusColor(for: label.segments[0].status, darkMenuBar: dark)),
                bottom: (label.segments[1].text, theme.menuBarStatusColor(for: label.segments[1].status, darkMenuBar: dark)),
                size: size, colonVisible: colonVisible
            )
        }
        if theme.isOutlined {
            // A printed theme's quota is a candy chip: its status colour,
            // inked, ink text — readable on a light or dark menu bar alike.
            let text = StatusBarPercentageImageRenderer.image(
                text: label.text, color: theme.textOnStatus, colonVisible: colonVisible
            )
            return StatusBarChipRenderer.chip(text, fill: theme.statusColor(for: label.status),
                                              ink: theme.glassBorder, shadow: theme.cardShadow != nil)
        }
        return StatusBarPercentageImageRenderer.image(
            text: label.text, color: theme.menuBarStatusColor(for: label.status, darkMenuBar: dark), colonVisible: colonVisible
        )
    }

    /// Template assets contain only the mark, never the colored tile. Custom or
    /// future providers without one use their configured SF Symbol. Account IDs
    /// resolve through the same visual identity lookup as colored icons.
    static func providerIcon(for providerId: String, native: Bool, dark: Bool) -> NSImage {
        let assetName = ProviderVisualIdentityLookup.iconAssetName(for: providerId)
        let ink: NSColor = dark ? .white : .black
        if native {
            if let mask = NSImage(named: assetName + "MenuBar") {
                return fittedProviderIcon(mask, ink: ink)
            }
            return symbolImage(ProviderVisualIdentityLookup.symbolIcon(for: providerId), color: ink)
        }
        guard let source = NSImage(named: assetName), source.size.width > 0, source.size.height > 0 else {
            return symbolImage(ProviderVisualIdentityLookup.symbolIcon(for: providerId), color: .labelColor)
        }
        return fittedProviderIcon(source)
    }

    /// Draw into our non-template composite: making only a child NSImage a
    /// template does not tint it once flattened with colored quota text. Fixed
    /// ink comes from the status button's actual appearance, not the app theme.
    /// Do not mutate NSImage(named:) instances shared by the popover.
    static func fittedProviderIcon(_ source: NSImage, ink: NSColor? = nil) -> NSImage {
        guard source.size.width > 0, source.size.height > 0 else { return NSImage(size: .zero) }
        let size = NSSize(width: 16, height: 16)
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let fitted = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let icon = NSImage(size: size, flipped: false) { bounds in
            let rect = NSRect(x: (bounds.width - fitted.width) / 2,
                              y: (bounds.height - fitted.height) / 2,
                              width: fitted.width, height: fitted.height)
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            if let ink {
                ink.setFill()
                bounds.fill(using: .sourceIn)
            }
            return true
        }
        icon.isTemplate = false
        return icon
    }

    /// The glyph shown while a Claude Code session is working.
    static let sessionGlyphSymbol = "terminal.fill"

    /// The symbol for the status icon drawn when there is no usage text, or
    /// nil when the session glyph stands in for it. A theme whose icon is the
    /// outline of the glyph (CLI's `terminal`) gets one terminal that fills in
    /// while Claude works, instead of an outline beside a filled copy.
    static func statusIconSymbol(theme: any AppThemeProvider, status: QuotaStatus,
                                 besideSessionGlyph: Bool) -> String? {
        guard let themeIcon = theme.statusBarIconName else {
            return fallbackIconName(for: status)
        }
        if besideSessionGlyph, sessionGlyphFillsIn(themeIcon) {
            return nil
        }
        return themeIcon
    }

    /// The session glyph's colour. It is the session phase colour, except when
    /// the glyph stands in for the theme's status icon: that one terminal is
    /// then the only place the quota status shows, so its shape says Claude is
    /// working and its colour keeps saying how the quota is doing. Otherwise a
    /// critical quota would look healthy for as long as a session runs.
    static func sessionGlyphColor(phase: ClaudeSession.Phase, theme: any AppThemeProvider,
                                  status: QuotaStatus, showsUsageText: Bool,
                                  darkMenuBar: Bool) -> Color {
        guard !showsUsageText, let themeIcon = theme.statusBarIconName,
              sessionGlyphFillsIn(themeIcon) else {
            return phase.color
        }
        return theme.menuBarStatusColor(for: status, darkMenuBar: darkMenuBar)
    }

    /// Whether a theme's icon is the outline of the session glyph.
    private static func sessionGlyphFillsIn(_ themeIcon: String) -> Bool {
        themeIcon + ".fill" == sessionGlyphSymbol
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

    // MARK: - Attachment Lifecycle

    /// Retry cadence for finding the status item: fast at first (it normally
    /// exists within a second of launch), then backing off to cover a slow
    /// first launch. Gives up after roughly two minutes.
    private static let attachRetryDelays: [Double] =
        Array(repeating: 0.25, count: 20)   // first 5s
        + Array(repeating: 1.0, count: 25)  // to 30s
        + Array(repeating: 5.0, count: 18)  // to ~2min

    /// Starts owning the status-item attachment instead of depending solely on
    /// MenuBarExtraAccess. Call once at app startup, alongside
    /// `startMonitoringLifecycle`.
    ///
    /// The library's introspection has two failure modes that both leave the
    /// menu bar permanently blank (issue #258): it hands over `statusItems[0]`,
    /// which on macOS 26 can be the button-less per-display replicant (see
    /// `attach`), and it polls for only two seconds before giving up for the
    /// rest of the app's lifetime. Since v0.4.69 every visible pixel is drawn
    /// into `button.image` — the SwiftUI label is a 1x1 transparent
    /// placeholder — so either failure means no icon, no width, and no way to
    /// open Settings.
    func startAttachLifecycle() {
        startAttachWatchdog()

        guard screenObserver == nil else { return }
        // Attaching or detaching a display rebuilds the status bar windows, so
        // the item we hold can turn into a replicant. Re-check on every change.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.revalidateAttachment() }
        }
    }

    /// Polls for a drawable status item until one turns up. A no-op while we
    /// already hold one, and while a poll is already running.
    private func startAttachWatchdog() {
        guard attachWatchdog == nil, statusItem?.button == nil else { return }
        attachWatchdog = Task { @MainActor [weak self] in
            // Release the slot however this ends, so a later display change can
            // start a fresh search instead of being locked out by a spent task.
            defer { self?.attachWatchdog = nil }
            for delay in Self.attachRetryDelays {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                guard self.statusItem?.button == nil else { return }
                guard let item = Self.drawableStatusItem() else { continue }
                AppLog.ui.notice("Attached to the status item via the watchdog")
                self.attach(item)
                return
            }
            AppLog.ui.error("No drawable status item found — the menu bar will stay blank")
        }
    }

    /// Drops an item we can no longer draw into and goes looking for the real
    /// one; otherwise just repaints, in case the menu bar was rebuilt stale.
    private func revalidateAttachment() {
        guard statusItem?.button == nil else {
            labelSync?.renderNow()
            return
        }
        statusItem = nil
        startAttachWatchdog()
    }

    /// The app's own status items, read the way AppKit exposes them: every
    /// `NSStatusBarWindow` carries its item under a private `statusItem` key.
    /// Only the real item has a button — the per-display replicants do not —
    /// so that, not position, is what identifies the one we can render into.
    private static func drawableStatusItem() -> NSStatusItem? {
        NSApplication.shared.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { window -> NSStatusItem? in
                guard window.responds(to: Selector(("statusItem"))) else { return nil }
                return window.value(forKey: "statusItem") as? NSStatusItem
            }
            .first { $0.button != nil }
    }

    // MARK: - Countdown Tick

    /// Half a second on, half a second off — the cadence a digital clock blinks
    /// its separator at. Also the rate the label re-reads the wall clock, so a
    /// countdown advances within half a second of the true minute boundary.
    private static let blinkInterval: TimeInterval = 0.5

    /// Starts watching whether a duration is shown at all, running the
    /// countdown tick only while one is. Sibling of `startMonitoringLifecycle`.
    ///
    /// Before this existed the label had no clock: the countdown text is
    /// computed fresh on every draw, but nothing *caused* a draw on a time
    /// basis. It advanced only as a side effect of something else changing — a
    /// probe result, a Claude Code hook event, opening the dropdown — so on an
    /// idle machine with background refresh off it could sit visibly stale.
    private func startBlinkLifecycle() {
        guard blinkSync == nil else { return }
        let sync = ObservationRenderSync<Bool>(
            read: { [self] in settings.menuBarDurationEnabled },
            render: { [self] showsDuration in
                showsDuration ? startBlinkTimer() : stopBlinkTimer()
            }
        )
        blinkSync = sync
        sync.start()
    }

    private func startBlinkTimer() {
        guard blinkTimer == nil else { return }
        let timer = Timer(timeInterval: Self.blinkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinkPhase.toggle()
                // refreshNow, not renderNow: the tick must keep the equality
                // check so a colon-less label ("2d") never repaints.
                self.labelSync?.refreshNow()
            }
        }
        // .common, not the default mode: a runloop in tracking mode (any menu
        // open) would otherwise stall the tick and freeze the colon mid-pulse.
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func stopBlinkTimer() {
        guard blinkTimer != nil else { return }
        blinkTimer?.invalidate()
        blinkTimer = nil
        // Never leave the colon parked in its dimmed phase.
        blinkPhase = true
        labelSync?.refreshNow()
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
        var seen = Set<String>()
        return ([monitor.selectedProviderId, settings.menuBarPercentageProviderId]
            + settings.menuBarAdditionalProviderIds)
            .filter { enabledProviderIds.contains($0) && seen.insert($0).inserted }
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
            // Each refresh tick imperatively forces a repaint. We can't rely on
            // the @Observable chain alone: after long idle it can stop delivering
            // invalidations (issue #192), freezing the menu-bar image even while
            // probes keep succeeding. renderNow() dedupes inside render(), so this
            // is cheap and only repaints when the composed image actually changed.
            for await _ in stream {
                self.labelSync?.renderNow()
            }
        }
    }
}

/// Pulses the separator colon of an H:MM countdown by fading it, shared by both
/// status-bar renderers.
///
/// Fading rather than hiding is deliberate. The label is drawn in
/// `monospacedDigitSystemFont`, where only the *digits* are fixed-width —
/// punctuation stays proportional. Substituting a space for the colon would
/// therefore change the label's width twice a second and shove every menu bar
/// item to its left. The glyph always draws at full size; only its alpha
/// changes, so the metrics are identical in both phases.
enum CountdownColonStyle {
    /// Alpha of the colon in its dimmed phase. Low enough to read as a pulse,
    /// high enough that the time never looks like it lost a character.
    private static let dimmedAlpha: CGFloat = 0.25

    /// Dims the countdown colons in `attributed` when the blink phase is off.
    /// A no-op in the visible phase, and for any text with no countdown colon.
    @MainActor
    static func apply(colonVisible: Bool, to attributed: NSMutableAttributedString, baseColor: Color) {
        guard !colonVisible else { return }
        let text = attributed.string
        let ranges = CountdownColon.ranges(in: text)
        guard !ranges.isEmpty else { return }

        let dimmed = NSColor(baseColor).withAlphaComponent(dimmedAlpha)
        for range in ranges {
            attributed.addAttribute(.foregroundColor, value: dimmed, range: NSRange(range, in: text))
        }
    }
}

/// Renders status text as an original-color image because macOS can ignore
/// `Text.foregroundStyle` inside a menu bar item.
/// A label drawn as a printed chip: a pill in `fill`, outlined in `ink`,
/// on a small hard shadow — sized to stay inside the menu bar's 22 pt.
enum StatusBarChipRenderer {
    static let outline: CGFloat = 1.5
    static let shadowOffset: CGFloat = 1.5

    @MainActor
    static func chip(_ content: NSImage, fill: Color, ink: Color, shadow: Bool) -> NSImage {
        let horizontalPadding: CGFloat = 6
        let pillHeight = min(content.size.height + 4, 19)
        let pillWidth = ceil(content.size.width) + horizontalPadding * 2
        let lift = shadow ? shadowOffset : 0
        let size = NSSize(width: pillWidth + lift + outline, height: pillHeight + lift + outline)
        let image = NSImage(size: size, flipped: false) { _ in
            // The pill sits top-left; its shadow falls down and to the right.
            let pill = NSRect(x: outline / 2, y: lift + outline / 2, width: pillWidth, height: pillHeight)
            let radius = pillHeight / 2
            if shadow {
                NSColor(ink).setFill()
                NSBezierPath(roundedRect: pill.offsetBy(dx: lift, dy: -lift), xRadius: radius, yRadius: radius).fill()
            }
            let path = NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius)
            NSColor(fill).setFill()
            path.fill()
            path.lineWidth = outline
            NSColor(ink).setStroke()
            path.stroke()
            let origin = NSPoint(x: pill.midX - content.size.width / 2, y: pill.midY - content.size.height / 2)
            content.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }
}

enum StatusBarPercentageImageRenderer {
    @MainActor
    static func image(text: String, color: Color, colonVisible: Bool = true) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(color),
        ]
        let attributedText = NSMutableAttributedString(string: text, attributes: attributes)
        CountdownColonStyle.apply(colonVisible: colonVisible, to: attributedText, baseColor: color)
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

/// Renders a dual-window label as two vertically stacked lines in one image,
/// so the label takes roughly half the menu bar width of the joined "A | B"
/// form. Sibling of `StatusBarPercentageImageRenderer`: same original-color
/// rationale (macOS can ignore `Text.foregroundStyle` in a menu bar item, and
/// each line must keep its own window's status color), but a smaller font so
/// both lines fit inside the menu bar's usable height.
///
/// The line size is user-selectable (`MenuBarStackedSize`): Small keeps the
/// original 9pt look, Medium and Large render 10pt and 11pt. At those larger
/// sizes the two natural line boxes no longer fit inside the 22pt clamp, so
/// the renderer verifies the two lines' measured glyph ink cannot collide and
/// switches anchoring strategies when it would (see `image(top:bottom:size:)`).
enum StatusBarStackedImageRenderer {
    /// The menu bar's usable content height. Status-item images taller than
    /// this get clipped or scaled by the system, so the stack never exceeds it.
    private static let maxHeight: CGFloat = 22

    /// Vertical breathing room between the two lines. When the two natural
    /// line heights plus this gap overflow `maxHeight`, the lines keep their
    /// top/bottom anchors and the overflow is absorbed by the gap and the
    /// fonts' descender space instead of clipping a line.
    private static let lineSpacing: CGFloat = 1

    /// Safety inset above the image's bottom edge when ink anchoring engages.
    /// AppKit's string drawing rounds baselines to pixel boundaries, which can
    /// land actual glyph pixels up to ~0.4pt below the analytic glyph-path
    /// bounds (measured), so pinning ink to exactly y = 0 could shave the
    /// bottom row off descenders.
    private static let bottomInkInset: CGFloat = 0.5

    @MainActor
    static func image(
        top: (text: String, color: Color),
        bottom: (text: String, color: Color),
        size: MenuBarStackedSize = .default,
        colonVisible: Bool = true
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size.stackedLinePointSize, weight: .semibold)
        // Each line carries its own countdown (or none), so each is styled
        // independently — but both share the phase, so the two colons pulse
        // together instead of drifting against each other.
        func attributedLine(_ line: (text: String, color: Color)) -> NSAttributedString {
            let attributed = NSMutableAttributedString(string: line.text, attributes: [
                .font: font,
                .foregroundColor: NSColor(line.color),
            ])
            CountdownColonStyle.apply(colonVisible: colonVisible, to: attributed, baseColor: line.color)
            return attributed
        }
        let topLine = attributedLine(top)
        let bottomLine = attributedLine(bottom)

        // Lines stay left-aligned: the image is as wide as the wider line and
        // both draw from x = 0, matching how the two windows read as a list.
        let width = ceil(max(topLine.size().width, bottomLine.size().width))
        let naturalHeight = topLine.size().height + lineSpacing + bottomLine.size().height
        let height = min(maxHeight, ceil(naturalHeight))

        // Default layout: line boxes anchored to the image edges, bottom line
        // at y = 0 and the top line's box against the top edge, with any clamp
        // deficit absorbed by the gap and the fonts' descender space. This is
        // the original Small rendering, byte-identical when no collision.
        var topOriginY = height - topLine.size().height
        var bottomOriginY: CGFloat = 0

        // Collision check: at 10pt a descender-bearing top line, and at 11pt
        // every realistic pairing, would let the glyphs themselves overlap
        // under box anchoring (measured -0.3 to -2.2pt of ink clearance).
        // When the measured glyph ink of the two lines would touch, switch to
        // INK anchoring: pin the bottom line's lowest ink just above y = 0 and
        // the top line's highest ink to the top edge. Line boxes may then
        // overflow the image, but a line box is mostly empty ascender and
        // descender allowance; reclaiming that padding restores over +3pt of
        // clearance at 11pt for realistic labels while nothing clips. Small
        // (9pt) always measures positive clearance here, so its rendering is
        // untouched. A line drawn at origin y has its baseline at
        // y + boxHeight - font.ascender, and ink bounds are baseline-relative.
        let topInk = inkBounds(of: topLine)
        let bottomInk = inkBounds(of: bottomLine)
        if !topInk.isNull, !bottomInk.isNull {
            let topInkBottom = topOriginY + topLine.size().height - font.ascender + topInk.minY
            let bottomInkTop = bottomOriginY + bottomLine.size().height - font.ascender + bottomInk.maxY
            if topInkBottom - bottomInkTop < 0 {
                bottomOriginY = bottomInkInset - (bottomLine.size().height - font.ascender) - bottomInk.minY
                topOriginY = height - (topLine.size().height - font.ascender) - topInk.maxY
            }
        }

        // flipped: false, so y grows upward: the bottom line sits at the
        // bottom and the top line is anchored to the image's top edge.
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            bottomLine.draw(at: NSPoint(x: 0, y: bottomOriginY))
            topLine.draw(at: NSPoint(x: 0, y: topOriginY))
            return true
        }
        image.isTemplate = false

        return image
    }

    /// Tight glyph-path bounds of the line's ink, relative to its baseline
    /// origin (CoreText convention: y = 0 is the baseline, descenders are
    /// negative). Null for a line with no ink, e.g. all whitespace.
    private static func inkBounds(of line: NSAttributedString) -> CGRect {
        CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(line), [.useGlyphPathBounds])
    }
}

extension MenuBarStackedSize {
    /// The point size each stacked line renders at. This mapping lives in the
    /// App layer (not Domain) because it is a rendering concern: Domain models
    /// the user's choice, the renderer decides what it means in points. The
    /// values are capped at 11pt because two lines of measured glyph ink must
    /// still fit inside the menu bar's 22pt content height (see
    /// `StatusBarStackedImageRenderer`).
    var stackedLinePointSize: CGFloat {
        switch self {
        case .small: 9
        case .medium: 10
        case .large: 11
        }
    }

    /// SF Symbol for the settings choice chip. Every chip in the menu bar
    /// section carries a leading icon, so the size options do too.
    var choiceIconName: String {
        switch self {
        case .small: "textformat.size.smaller"
        case .medium: "textformat.size"
        case .large: "textformat.size.larger"
        }
    }
}
