import Foundation

/// A fully composed menu bar label: the rendered text plus the worst-case
/// status across all quota windows it represents.
///
/// Built by `QuotaMonitor.menuBarLabel(...)`. When two quota windows are shown
/// together (e.g. session + weekly), each window is prefixed with its
/// `QuotaType.shortLabel` so the numbers stay distinguishable, and the overall
/// status is the most severe of the shown windows. The per-window breakdown is
/// also kept in `segments` so renderers that draw the windows individually
/// (the stacked menu bar mode) can tint each one by its own status.
public struct MenuBarLabel: Sendable, Equatable {
    /// One quota window's slice of the label: its rendered text (including the
    /// `QuotaType.shortLabel` prefix when two windows are shown) and that
    /// window's own status, before the worst-case merge that produces the
    /// label-level `status`.
    public struct Segment: Sendable, Equatable {
        public let text: String
        public let status: QuotaStatus

        public init(text: String, status: QuotaStatus) {
            self.text = text
            self.status = status
        }
    }

    public let text: String
    public let status: QuotaStatus

    /// The per-window segments behind `text`, in display order. Always holds
    /// at least one entry: single-window labels carry one segment mirroring
    /// `text` and `status` exactly, dual-window labels carry one per window.
    public let segments: [Segment]

    /// `segments` defaults to a single segment mirroring `text`/`status`, so
    /// pre-existing call sites (and single-window labels) need no changes.
    public init(text: String, status: QuotaStatus, segments: [Segment]? = nil) {
        self.text = text
        self.status = status
        self.segments = segments ?? [Segment(text: text, status: status)]
    }
}

/// Provider identity stays separate from quota text so renderers can show an
/// icon while retaining a named tooltip and accessibility description.
public struct MenuBarProviderLabel: Sendable, Equatable {
    public let providerId: String
    public let providerName: String
    public let stacked: Bool
    public let stackedSize: MenuBarStackedSize
    public let label: MenuBarLabel

    public var text: String { "\(providerName) \(label.text)" }
    public var status: QuotaStatus { label.status }

    public init(providerId: String, providerName: String, label: MenuBarLabel,
                stacked: Bool = false, stackedSize: MenuBarStackedSize = .default) {
        self.providerId = providerId
        self.providerName = providerName
        self.stacked = stacked
        self.stackedSize = stackedSize
        self.label = label
    }
}
