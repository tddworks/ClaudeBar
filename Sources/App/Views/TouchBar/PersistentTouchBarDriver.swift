import AppKit
import Domain
import Infrastructure

// MARK: - Persistent Touch Bar Driver

/// Manages an always-on, system-wide Touch Bar interface.
/// Uses macOS system modal presentation (placement 0) so it remains visible across all applications and windows.
@MainActor
public final class PersistentTouchBarDriver: NSObject, NSTouchBarDelegate {
    public static let shared = PersistentTouchBarDriver()

    private let sceneId = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.scene")
    private let emptyId = NSTouchBarItem.Identifier("com.tddworks.claudebar.touchbar.empty")

    private var touchBar: NSTouchBar?
    private var quotaView: TouchBarQuotaView?
    private var monitor: QuotaMonitor?
    private var settings: AppSettings?
    private var sessionMonitor: SessionMonitor?

    private var sync: ObservationRenderSync<[TouchBarProviderGauge]>?
    private var isPresented = false
    private var activateObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func configure(monitor: QuotaMonitor, settings: AppSettings, sessionMonitor: SessionMonitor? = nil) {
        self.monitor = monitor
        self.settings = settings
        self.sessionMonitor = sessionMonitor
    }

    /// Trigger the refresh-pulse animation on the quota view.
    public func triggerRefreshPulse() {
        quotaView?.triggerRefreshPulse()
    }

    public func start() {
        guard self.monitor != nil, self.settings != nil, sync == nil else { return }

        // 1. Build View and TouchBar
        let view = TouchBarQuotaView(frame: NSRect(x: 0, y: 0, width: TouchBarQuotaView.sceneW, height: TouchBarQuotaView.sceneH))
        self.quotaView = view

        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [sceneId]
        bar.escapeKeyReplacementItemIdentifier = emptyId
        self.touchBar = bar

        // 2. Continuous State Sync
        let newSync = ObservationRenderSync(
            read: { [self] in buildGauges() },
            render: { [self] gauges in updateGauges(gauges) }
        )
        self.sync = newSync
        newSync.start()

        // 3. Re-assert on application switch (cheap and idempotent)
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presentIfNeeded()
            }
        }

        // 4. Re-assert when screen unlocks
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presentIfNeeded()
            }
        }

        presentIfNeeded()
    }

    public func stop() {
        dismiss()
        sync?.stop()
        sync = nil
        quotaView = nil
        touchBar = nil

        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
            self.activateObserver = nil
        }
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
    }

    // MARK: - State Observation

    private func buildGauges() -> [TouchBarProviderGauge] {
        guard let monitor, let settings, settings.touchBarEnabled else {
            return []
        }

        let providerIds = settings.menuBarProviderIds
        guard !providerIds.isEmpty else { return [] }

        var gauges: [TouchBarProviderGauge] = []

        for providerId in providerIds {
            // Fall back to the globally selected provider only for the primary slot
            guard let provider = monitor.provider(for: providerId) else { continue }
            let config = settings.menuBarConfiguration(for: providerId)
            let snapshot = provider.snapshot
            let quotas = snapshot?.quotas ?? []

            // Resolve primary quota: match by configured key or fallback to first quota
            let primaryQuota = quotas.first { $0.quotaType.quotaKey == config.primaryQuotaKey }
                ?? quotas.first

            // Resolve secondary quota if configured for this provider
            let secondaryQuota: UsageQuota?
            if !config.secondaryQuotaKey.isEmpty,
               config.secondaryQuotaKey != (primaryQuota?.quotaType.quotaKey ?? "") {
                secondaryQuota = quotas.first { $0.quotaType.quotaKey == config.secondaryQuotaKey }
            } else {
                secondaryQuota = nil
            }

            let items: [UsageQuota?]
            if let primaryQuota, let secondaryQuota {
                items = [primaryQuota, secondaryQuota]
            } else if let primaryQuota {
                items = [primaryQuota]
            } else {
                // Provider exists but has no quota data yet (awaiting probe or unconfigured).
                // Keep a placeholder so it appears on the Touch Bar.
                items = [nil]
            }

            let isMultipleQuota = items.count > 1
            for quota in items {
                let (gaugeProviderId, gaugeName) = resolveIdentity(
                    for: quota,
                    provider: provider,
                    isMultiple: isMultipleQuota,
                    settings: settings
                )
                let pct = quota.map { max(0, min(100, Double($0.displayPercent(mode: settings.usageDisplayMode)))) } ?? 0.0
                let resetText = quota.flatMap { formatResetText(for: $0) }
                let status = (settings.burnRateWarningEnabled
                    ? quota?.paceAwareStatus(burnRateThreshold: settings.burnRateThreshold)
                    : quota?.status) ?? snapshot?.overallStatus ?? .healthy
                let hasQuota = (quota != nil)

                gauges.append(TouchBarProviderGauge(
                    providerId: gaugeProviderId,
                    name: gaugeName,
                    percentUsed: pct,
                    resetText: resetText,
                    status: status,
                    hasQuota: hasQuota
                ))
            }
        }

        return gauges
    }

    private func resolveIdentity(
        for quota: UsageQuota?,
        provider: any AIProvider,
        isMultiple: Bool,
        settings: AppSettings
    ) -> (providerId: String, name: String) {
        if provider.id.lowercased() == "antigravity" {
            if isMultiple, let quota {
                let compact = quota.menuBarTitle ?? quota.compactTitle ?? quota.quotaType.displayName
                if !compact.isEmpty {
                    return (provider.id, compact)
                }
            }
            return (provider.id, "Antigravity")
        }

        let baseName = provider.name
        if isMultiple, let quota {
            let compact = quota.menuBarTitle ?? quota.compactTitle ?? quota.quotaType.shortLabel
            if !compact.isEmpty, !baseName.localizedCaseInsensitiveContains(compact) {
                return (provider.id, "\(baseName) \(compact)")
            }
        }
        return (provider.id, baseName)
    }

    private func formatResetText(for quota: UsageQuota) -> String? {
        if let compact = quota.compactResetTime, !compact.isEmpty {
            return compact
        }
        if let resetsAt = quota.resetsAt {
            let diff = Int(resetsAt.timeIntervalSinceNow)
            guard diff > 0 else { return nil }
            if diff >= 86400 {
                return "\(diff / 86400)d"
            } else if diff >= 3600 {
                let h = diff / 3600
                let m = (diff % 3600) / 60
                return String(format: "%d:%02d", h, m)
            } else {
                let m = max(1, diff / 60)
                return "\(m)m"
            }
        }
        if let raw = quota.resetText, !raw.isEmpty {
            let trimmed = raw
                .replacingOccurrences(of: "Resets in ", with: "")
                .replacingOccurrences(of: "Resets ", with: "")
                .trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private func updateGauges(_ gauges: [TouchBarProviderGauge]) {
        quotaView?.gauges = gauges
        quotaView?.sessionActive = sessionMonitor?.hasActiveSession ?? false

        if let settings, settings.touchBarEnabled, !gauges.isEmpty {
            presentIfNeeded()
        } else {
            dismiss()
        }
    }

    // MARK: - System Modal Presentation

    public func presentIfNeeded() {
        guard let touchBar, let settings, settings.touchBarEnabled else { return }

        // Hide close box so it runs as an unobtrusive persistent bar
        typealias CloseBoxFunc = @convention(c) (Bool) -> Void
        if let dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW) {
            if let sym = dlsym(dfr, "DFRSystemModalShowsCloseBoxWhenFrontMost") {
                let fn = unsafeBitCast(sym, to: CloseBoxFunc.self)
                fn(false)
            }
            dlclose(dfr)
        }

        typealias PresentModalFunc = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString?) -> Void
        let sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        if let method = class_getClassMethod(NSTouchBar.self, sel) {
            let imp = method_getImplementation(method)
            let presentModal = unsafeBitCast(imp, to: PresentModalFunc.self)
            presentModal(NSTouchBar.self, sel, touchBar, 0, nil)
            isPresented = true
            DispatchQueue.main.async { [weak self] in
                self?.hideCloseButtons()
            }
        }
    }

    public func dismiss() {
        guard let touchBar, isPresented else { return }

        typealias DismissModalFunc = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        let sel = NSSelectorFromString("dismissSystemModalTouchBar:")
        if let method = class_getClassMethod(NSTouchBar.self, sel) {
            let imp = method_getImplementation(method)
            let dismissModal = unsafeBitCast(imp, to: DismissModalFunc.self)
            dismissModal(NSTouchBar.self, sel, touchBar)
            isPresented = false
        }
    }

    private func hideCloseButtons() {
        guard let cls = NSClassFromString("NSFunctionRow") as? NSObject.Type else { return }
        let sel = NSSelectorFromString("_topLevelFunctionRowViews")
        guard cls.responds(to: sel),
              let views = cls.perform(sel)?.takeUnretainedValue() as? [NSView] else { return }
        for topView in views {
            stripCloseButtons(in: topView)
        }
    }

    private func stripCloseButtons(in view: NSView) {
        if let btn = view as? NSButton {
            let title = btn.title.lowercased()
            let imgName = btn.image?.name() ?? ""
            if title == "x" || title == "esc" || imgName.contains("close") || imgName.contains("dismiss") || btn.action == NSSelectorFromString("dismiss:") {
                btn.isHidden = true
                btn.frame = .zero
            }
        }
        for sub in view.subviews {
            stripCloseButtons(in: sub)
        }
    }

    // MARK: - NSTouchBarDelegate

    public func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == sceneId, let quotaView {
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = quotaView
            return item
        } else if identifier == emptyId {
            let item = NSCustomTouchBarItem(identifier: identifier)
            let empty = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 30))
            empty.isHidden = true
            item.view = empty
            return item
        }
        return nil
    }
}
