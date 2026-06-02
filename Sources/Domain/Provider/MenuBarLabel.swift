import Foundation

/// A fully composed menu bar label: the rendered text plus the worst-case
/// status across all quota windows it represents.
///
/// Built by `QuotaMonitor.menuBarLabel(...)`. When two quota windows are shown
/// together (e.g. session + weekly), each window is prefixed with its
/// `QuotaType.shortLabel` so the numbers stay distinguishable, and the overall
/// status is the most severe of the shown windows.
public struct MenuBarLabel: Sendable, Equatable {
    public let text: String
    public let status: QuotaStatus

    public init(text: String, status: QuotaStatus) {
        self.text = text
        self.status = status
    }
}
