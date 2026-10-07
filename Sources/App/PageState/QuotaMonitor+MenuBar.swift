import Kit
import Foundation

// The menu bar's labels, built from the monitor's quotas — page state (MODULAR_DESIGN §6):
// what the menu bar prints is the App's, read from what Kotlin's monitor holds.
extension QuotaMonitor {
    /// Returns the menu bar percentage display for a provider/quota selection.
    func menuBarPercentageDisplay(
        providerId: String,
        quotaKey: String,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> MenuBarPercentageDisplay? {
        guard let quota = quota(providerId: providerId, quotaKey: quotaKey) else {
            return nil
        }

        return MenuBarPercentageDisplay(
            quota: quota,
            mode: mode,
            burnRateWarningEnabled: burnRateWarningEnabled,
            burnRateThreshold: burnRateThreshold
        )
    }

    /// Returns the menu bar duration display for a provider/quota selection.
    /// Sibling to `menuBarPercentageDisplay`; both use the same selectors.
    func menuBarDurationDisplay(
        providerId: String,
        quotaKey: String,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> MenuBarDurationDisplay? {
        guard let quota = quota(providerId: providerId, quotaKey: quotaKey) else {
            return nil
        }

        return MenuBarDurationDisplay(
            quota: quota,
            burnRateWarningEnabled: burnRateWarningEnabled,
            burnRateThreshold: burnRateThreshold
        )
    }

    /// Additional providers use their first quota and include a name so adjacent
    /// readouts remain distinguishable. Enabled providers awaiting data keep a placeholder.
    func additionalMenuBarLabels(
        providerIds: [String],
        configurations: [String: MenuBarProviderSettings] = [:],
        showPercentage: Bool,
        showDuration: Bool,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> [MenuBarProviderLabel] {
        guard showPercentage || showDuration else { return [] }
        var seen = Set<String>()
        return providerIds.filter { seen.insert($0).inserted }.prefix(2).compactMap { id in
            guard let provider = lineup.first(where: { $0.id == id }) else { return nil }
            let config = configurations[id] ?? MenuBarProviderSettings()
            let key = config.primaryQuotaKey.isEmpty
                ? usage(of: provider)?.quotas.first?.quotaType.quotaKey : config.primaryQuotaKey
            guard let key,
                  let label = menuBarLabel(
                    providerId: id, primaryQuotaKey: key, secondaryQuotaKey: config.secondaryQuotaKey,
                    showPercentage: showPercentage, showDuration: showDuration,
                    mode: mode, burnRateWarningEnabled: burnRateWarningEnabled,
                    burnRateThreshold: burnRateThreshold
                  ) else {
                return MenuBarProviderLabel(providerId: id, providerName: lineupName(of: provider),
                                            label: MenuBarLabel(text: "—", status: .healthy))
            }
            return MenuBarProviderLabel(providerId: id, providerName: lineupName(of: provider), label: label,
                                        stacked: config.stacked, stackedSize: MenuBarStackedSize(storedRawValue: config.stackedSize))
        }
    }

    /// Builds the fully composed menu bar label for one or two quota windows.
    ///
    /// The primary window renders exactly as the single-window label always has
    /// (percentage and/or duration joined by " · "). When `secondaryQuotaKey` is
    /// non-empty and differs from the primary, a second window is appended: each
    /// window is prefixed with the quota's `menuBarTitle` when the probe set one
    /// (a condensed form of labels too wide for the menu bar), otherwise its
    /// `QuotaType.shortLabel`, and the two are joined by " | ", e.g.
    /// "5h 12% | 7d 34%". The status is the most severe of the
    /// shown windows, and each window is also exposed individually via
    /// `MenuBarLabel.segments` for renderers that draw them on separate lines.
    ///
    /// Returns nil when neither percentage nor duration is enabled, or when no
    /// quota data is available for the requested windows.
    func menuBarLabel(
        providerId: String,
        primaryQuotaKey: String,
        secondaryQuotaKey: String = "",
        showPercentage: Bool,
        showDuration: Bool,
        mode: UsageDisplayMode,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) -> MenuBarLabel? {
        let primaryQuotaKey = primaryQuotaKey.isEmpty
            ? (lineup.first { $0.id == providerId }.flatMap { usage(of: $0) }?.quotas.first?.quotaType.quotaKey ?? "")
            : primaryQuotaKey
        func segment(forQuotaKey quotaKey: String) -> (text: String, status: QuotaStatus)? {
            let percentage = showPercentage
                ? menuBarPercentageDisplay(
                    providerId: providerId,
                    quotaKey: quotaKey,
                    mode: mode,
                    burnRateWarningEnabled: burnRateWarningEnabled,
                    burnRateThreshold: burnRateThreshold
                )
                : nil
            let duration = showDuration
                ? menuBarDurationDisplay(
                    providerId: providerId,
                    quotaKey: quotaKey,
                    burnRateWarningEnabled: burnRateWarningEnabled,
                    burnRateThreshold: burnRateThreshold
                )
                : nil

            switch (percentage, duration) {
            case let (.some(percentage), .some(duration)):
                return ("\(percentage.text) · \(duration.text)", percentage.status)
            case let (.some(percentage), .none):
                return (percentage.text, percentage.status)
            case let (.none, .some(duration)):
                return (duration.text, duration.status)
            case (.none, .none):
                return nil
            }
        }

        let primary = segment(forQuotaKey: primaryQuotaKey)
        let secondary = (!secondaryQuotaKey.isEmpty && secondaryQuotaKey != primaryQuotaKey)
            ? segment(forQuotaKey: secondaryQuotaKey)
            : nil

        switch (primary, secondary) {
        case let (.some(primary), .some(secondary)):
            // Window prefix: the quota's own condensed menu-bar title wins
            // (probes set it when the full label is too wide, e.g. a long
            // account discriminator), then the type's short label.
            func windowPrefix(forQuotaKey quotaKey: String) -> String {
                if let title = quota(providerId: providerId, quotaKey: quotaKey)?.menuBarTitle {
                    return title
                }
                return QuotaType(quotaKey: quotaKey)?.shortLabel ?? quotaKey
            }
            let primaryLabel = windowPrefix(forQuotaKey: primaryQuotaKey)
            let secondaryLabel = windowPrefix(forQuotaKey: secondaryQuotaKey)
            // Each window becomes its own segment (prefixed text + that
            // window's status) so stacked rendering can draw and tint them
            // independently; the joined text stays the canonical single-line
            // form and doubles as the tooltip.
            let primarySegment = MenuBarLabel.Segment(
                text: "\(primaryLabel) \(primary.text)",
                status: primary.status
            )
            let secondarySegment = MenuBarLabel.Segment(
                text: "\(secondaryLabel) \(secondary.text)",
                status: secondary.status
            )
            return MenuBarLabel(
                text: "\(primarySegment.text) | \(secondarySegment.text)",
                status: max(primary.status, secondary.status),
                segments: [primarySegment, secondarySegment]
            )
        case let (.some(primary), .none):
            return MenuBarLabel(text: primary.text, status: primary.status)
        case let (.none, .some(secondary)):
            return MenuBarLabel(text: secondary.text, status: secondary.status)
        case (.none, .none):
            return nil
        }
    }

}
