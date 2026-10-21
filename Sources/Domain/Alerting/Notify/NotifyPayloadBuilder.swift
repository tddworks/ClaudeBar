import Quotas
import DataSources
import Providers
import Foundation

/// Turns quota readings into the tile and gauge ClaudeBar publishes to Notify!.
///
/// This is the whole decision layer of the feature and it is deliberately pure:
/// no clock of its own, no network, no settings lookups. What to show, in what
/// order, in what words, and in what color is decided here so it can be tested
/// as plain state assertions.
///
/// The rules:
/// 1. The worst quota leads. Readings sort by status severity, then by how
///    little is left, so the number that needs attention is the headline and
///    the tile takes its color and progress bar from it.
/// 2. The row's arrangement is the reader's choice: a ranking of the worst
///    quotas, or a fixed arrangement where each provider's windows sit
///    together and stay where they are. The headline is the same either way.
/// 3. The tile carries up to six windows as a metrics row, because six is the
///    gateway's ceiling and more than six is unreadable on a Lock Screen.
/// 4. Labels drop the provider name when every reading comes from the same
///    provider, so a single provider tile reads "5h  7d" rather than
///    "Claude 5h  Claude 7d".
/// 5. Percentages are remaining, not used. Every ClaudeBar surface reads that
///    way, and a full bar meaning a full quota is the only intuitive mapping
///    a gauge has.
public struct NotifyPayloadBuilder: Sendable {
    /// The tile and widget title. Both name the sending app rather than the
    /// current quota: the gateway treats a title as an identity, and a widget
    /// that renamed itself whenever the user switched provider would be
    /// unrecognizable in the phone's widget picker.
    public static let defaultTitle = "ClaudeBar"

    /// What a cell shows while the window it stands for is not reporting.
    ///
    /// A dash rather than a number, because the gateway requires a value and
    /// because an empty cell should still read as a cell rather than as a
    /// gap in the row.
    static let emptyValue = "—"

    private let title: String

    public init(title: String = NotifyPayloadBuilder.defaultTitle) {
        self.title = title
    }

    public func payload(
        readings: [NotifyQuotaReading],
        gaugeSelection: NotifyGaugeSelection = .automatic,
        includesTile: Bool = true,
        includesGauge: Bool = true,
        includesScreenTile: Bool = true,
        statusPolicy: StatusPolicy = .absolute,
        tileOrder: NotifyTileOrder = .worstFirst,
        previousSlots: [NotifySlot] = []
    ) -> NotifyPayload {
        let ordered = Self.ordered(readings, under: statusPolicy)
        guard let headline = ordered.first else { return .empty }

        let cells = Self.cells(ordered: ordered, order: tileOrder, keeping: previousSlots)

        // The name is dropped when everything ClaudeBar knows about comes from
        // one provider, not when the cells that fit happen to be one
        // provider's: a row that names its provider stays a row that names it,
        // whether the row is a ranking or a fixed arrangement.
        let omitsProviderName = Set(ordered.map(\.providerId)).count == 1

        // The Live Activity and the Home Screen tile are built once and shared.
        // The gateway takes the same body on both routes, so building them twice
        // could only produce two things that were supposed to be identical and
        // one day were not.
        let tile = (includesTile || includesScreenTile)
            ? self.tile(
                cells: cells,
                omitsProviderName: omitsProviderName,
                ordered: ordered,
                headline: headline,
                policy: statusPolicy
            )
            : nil

        return NotifyPayload(
            tile: includesTile ? tile : nil,
            gauge: includesGauge ? gauge(ordered: ordered, headline: headline, selection: gaugeSelection, policy: statusPolicy) : nil,
            screenTile: includesScreenTile ? tile : nil
        )
    }

    // MARK: - Ordering

    /// Worst first, and fully deterministic: two payloads built from the same
    /// readings must compare equal, or the driver would republish forever.
    static func ordered(_ readings: [NotifyQuotaReading], under policy: StatusPolicy = .absolute) -> [NotifyQuotaReading] {
        readings.sorted { left, right in
            let leftStatus = left.quota.status(under: policy)
            let rightStatus = right.quota.status(under: policy)
            if leftStatus != rightStatus { return leftStatus > rightStatus }
            if left.quota.percentRemaining != right.quota.percentRemaining {
                return left.quota.percentRemaining < right.quota.percentRemaining
            }
            if left.providerName != right.providerName { return left.providerName < right.providerName }
            if left.quota.quotaType.quotaKey != right.quota.quotaType.quotaKey {
                return left.quota.quotaType.quotaKey < right.quota.quotaType.quotaKey
            }
            // The last tie break, and the one that makes the comparator total.
            // Display names are not unique: an aggregating provider can report
            // two accounts under one name, and Swift's sort is not stable, so
            // without this two readings that tie on everything else could come
            // back in either order. The payload would then differ between builds
            // of the same state and the driver would republish for nothing.
            return left.providerId < right.providerId
        }
    }

    // MARK: - The row's cells

    /// One cell of the tile's metrics row.
    private enum Cell {
        /// A window that is reporting.
        case reading(NotifyQuotaReading, slot: NotifySlot)

        /// A window that stopped reporting. The cell keeps its place, so the
        /// cells after it do not slide over.
        case empty(NotifySlot, providerName: String)

        var slot: NotifySlot {
            switch self {
            case .reading(_, let slot): slot
            case .empty(let slot, _): slot
            }
        }

        var providerId: String { slot.providerId }
    }

    /// The cells of the row, in the order they appear.
    ///
    /// `previousSlots` are the cells the tile showed last time, and they are
    /// what lets a window that stopped reporting keep its place.
    private static func cells(
        ordered: [NotifyQuotaReading],
        order: NotifyTileOrder,
        keeping previousSlots: [NotifySlot]
    ) -> [Cell] {
        switch order {
        case .worstFirst:
            return ordered.prefix(NotifyLimits.metricCount).map { .reading($0, slot: Self.slot(for: $0)) }
        case .fixed:
            return fixedCells(ordered: ordered, keeping: previousSlots)
        }
    }

    /// The cells of a fixed row: providers in name order, and within a
    /// provider the short-term window before the weekly one.
    private static func fixedCells(
        ordered: [NotifyQuotaReading],
        keeping previousSlots: [NotifySlot]
    ) -> [Cell] {
        let names = Dictionary(
            ordered.map { ($0.providerId, $0.providerName) },
            uniquingKeysWith: { first, _ in first }
        )

        let live = ordered.map { reading in
            Cell.reading(reading, slot: Self.slot(for: reading))
        }

        // A cell whose window stopped reporting keeps its place, for as long as
        // its provider reports something at all. A provider that stopped
        // reporting has gone, and its cells go with it rather than standing
        // empty forever.
        let empty = previousSlots
            .filter { previous in
                !live.contains(where: { $0.slot.standsFor(previous) })
                    && live.contains(where: { $0.providerId == previous.providerId })
            }
            .map { previous in
                Cell.empty(previous, providerName: names[previous.providerId] ?? previous.providerId)
            }

        let all = (live + empty)
            .map { (key: arrangementKey(for: $0, names: names), cell: $0) }
            .sorted { $0.key < $1.key }
            .map(\.cell)

        // The row holds six cells, the gateway's ceiling. A reading never loses
        // its cell to an empty one: the empty cells take what is left over.
        let room = max(0, NotifyLimits.metricCount - live.count)
        var empties = 0
        let kept = all.filter { cell in
            guard case .empty = cell else { return true }
            defer { empties += 1 }
            return empties < room
        }

        return Array(kept.prefix(NotifyLimits.metricCount))
    }

    /// The cell a reading stands for.
    private static func slot(for reading: NotifyQuotaReading) -> NotifySlot {
        NotifySlot(
            providerId: reading.providerId,
            quotaKey: reading.quota.quotaType.quotaKey,
            windowLabel: Self.windowLabel(for: reading.quota)
        )
    }

    /// What a fixed row is arranged by.
    ///
    /// The provider's name, then the provider itself, so two providers that
    /// share a name don't interleave their windows; then where the window sits
    /// among its provider's windows, the window's own key, and last the value
    /// the cell shows.
    /// The last one is there so that two cells which would look the same come
    /// back in the same order every time, which is what keeps two payloads
    /// built from the same readings equal.
    private static func arrangementKey(
        for cell: Cell,
        names: [String: String]
    ) -> (String, String, Int, String, String, String) {
        let slot = cell.slot
        let value: String
        switch cell {
        case .reading(let reading, _): value = Self.headlineValue(for: reading.quota)
        case .empty: value = emptyValue
        }
        return (
            names[slot.providerId] ?? "",
            slot.providerId,
            windowRank(quotaKey: slot.quotaKey),
            slot.quotaKey,
            slot.windowLabel,
            value
        )
    }

    /// Where a window sits among its provider's windows: the short-term one
    /// before the weekly one, and anything else after both.
    ///
    /// The rank comes from the window's key rather than from its quota type,
    /// because a cell whose window stopped reporting has a key and no type.
    private static func windowRank(quotaKey: String) -> Int {
        if quotaKey == QuotaType.session.quotaKey { return 0 }
        if quotaKey == QuotaType.weekly.quotaKey { return 1 }
        if quotaKey.hasPrefix("model:") { return 2 }
        return 3
    }

    // MARK: - Tile

    private func tile(
        cells: [Cell],
        omitsProviderName: Bool,
        ordered: [NotifyQuotaReading],
        headline: NotifyQuotaReading,
        policy: StatusPolicy
    ) -> NotifyTile? {
        let metrics = cells.compactMap { cell -> NotifyMetric? in
            switch cell {
            case .reading(let reading, let slot):
                return NotifyMetric(
                    slot: slot,
                    label: Self.label(for: reading, omittingProviderName: omitsProviderName),
                    value: Self.headlineValue(for: reading.quota),
                    unit: Self.unit(for: reading.quota),
                    tintHex: reading.quota.status(under: policy).notifyTintHex
                )
            case .empty(let slot, let providerName):
                return NotifyMetric(
                    slot: slot,
                    label: Self.label(
                        for: slot,
                        providerName: providerName,
                        omittingProviderName: omitsProviderName
                    ),
                    value: Self.emptyValue,
                    unit: nil,
                    tintHex: nil
                )
            }
        }

        return NotifyTile(
            title: title,
            body: Self.summary(for: headline),
            symbolName: NotifySymbol.quota,
            tintHex: headline.quota.status(under: policy).notifyTintHex,
            progress: Self.progress(for: ordered),
            trailing: headline.quota.compactResetTime,
            metrics: metrics
        )
    }

    // MARK: - Gauge

    private func gauge(
        ordered: [NotifyQuotaReading],
        headline: NotifyQuotaReading,
        selection: NotifyGaugeSelection,
        policy: StatusPolicy
    ) -> NotifyGauge? {
        let shown = Self.selected(from: ordered, selection: selection) ?? headline

        return NotifyGauge(
            title: title,
            value: Self.headlineValue(for: shown.quota),
            unit: Self.unit(for: shown.quota),
            detail: Self.gaugeDetail(for: shown),
            symbolName: NotifySymbol.quota,
            tintHex: shown.quota.status(under: policy).notifyTintHex,
            progress: shown.quota.isDollarBased ? nil : shown.quota.percentRemaining
        )
    }

    /// The reading the user asked the gauge to show, or nil when the selection
    /// is automatic or names a window that is no longer reporting.
    static func selected(
        from readings: [NotifyQuotaReading],
        selection: NotifyGaugeSelection
    ) -> NotifyQuotaReading? {
        guard !selection.isAutomatic else { return nil }
        return readings.first {
            $0.providerId == selection.providerId
                && $0.quota.quotaType.quotaKey == selection.quotaKey
        }
    }

    // MARK: - Words and numbers

    /// "Claude 5h", or just "5h" when the tile only covers one provider.
    static func label(for reading: NotifyQuotaReading, omittingProviderName: Bool) -> String {
        let window = Self.windowLabel(for: reading.quota)
        guard !omittingProviderName else { return window }
        return "\(reading.providerName) \(window)"
    }

    /// The label of a cell whose window stopped reporting: the same words the
    /// cell wore while the window was reporting.
    static func label(for slot: NotifySlot, providerName: String, omittingProviderName: Bool) -> String {
        guard !omittingProviderName else { return slot.windowLabel }
        return "\(providerName) \(slot.windowLabel)"
    }

    /// The quota's own short title when its probe set one, otherwise the
    /// window's short label ("5h", "7d").
    static func windowLabel(for quota: UsageQuota) -> String {
        quota.compactTitle ?? quota.quotaType.shortLabel
    }

    /// A percentage as a bare integer, or the formatted balance for a quota
    /// measured in money rather than percent.
    static func headlineValue(for quota: UsageQuota) -> String {
        if let balance = quota.formattedDollarRemaining { return balance }
        return "\(Int(quota.percentRemaining.rounded()))"
    }

    static func unit(for quota: UsageQuota) -> String? {
        quota.isDollarBased ? nil : "%"
    }

    /// "Claude 5h, 42% left, resets in 2:14". The tile's body line, which the
    /// gateway shows only when there are no metrics to put in its place, so it
    /// has to carry the number itself.
    static func summary(for reading: NotifyQuotaReading) -> String {
        var parts = ["\(reading.providerName) \(Self.windowLabel(for: reading.quota))"]

        if let balance = reading.quota.formattedDollarRemaining {
            parts.append("\(balance) left")
        } else {
            parts.append("\(Int(reading.quota.percentRemaining.rounded()))% left")
        }

        if let resets = reading.quota.compactResetTime {
            parts.append(resets == "soon" ? "resets soon" : "resets in \(resets)")
        }

        return parts.joined(separator: ", ")
    }

    /// "Claude 5h, resets in 2:14". The widget's quieter line, which sits next
    /// to a headline value that already shows the percentage, so repeating it
    /// here would waste the one short line the widget has.
    static func gaugeDetail(for reading: NotifyQuotaReading) -> String {
        var parts = ["\(reading.providerName) \(Self.windowLabel(for: reading.quota))"]

        if let resets = reading.quota.compactResetTime {
            parts.append(resets == "soon" ? "resets soon" : "resets in \(resets)")
        }

        return parts.joined(separator: ", ")
    }

    /// The bar on the tile. Money-based quotas have no percentage to draw, so
    /// the bar falls through to the worst quota that does have one rather than
    /// disappearing whenever a credit balance happens to be the headline.
    static func progress(for ordered: [NotifyQuotaReading]) -> Double? {
        ordered.first { !$0.quota.isDollarBased }?.quota.percentRemaining
    }
}
