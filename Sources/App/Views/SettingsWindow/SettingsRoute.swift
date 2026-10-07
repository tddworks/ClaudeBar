import Observation

/// A request to open Settings on one pane, from outside the window: the
/// popover's *Leave and delete my data…* opens it on Leaderboard.
@MainActor
@Observable
final class SettingsRoute {
    static let shared = SettingsRoute()

    private(set) var requested: SettingsSection?

    func open(_ section: SettingsSection) {
        requested = section
    }

    /// The pane asked for, once: the window takes it and the request is spent.
    func take() -> SettingsSection? {
        defer { requested = nil }
        return requested
    }
}
