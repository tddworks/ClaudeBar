import Foundation

/// Navigation model for the standalone Settings window sidebar.
/// Sections are grouped the way the sidebar renders them:
/// App → Monitoring → System.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case menuBar
    case providers
    case syncAlerts
    case hooks
    case notify
    case updates
    case logs
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBar: "Menu Bar"
        case .providers: "Providers"
        case .syncAlerts: "Sync & Alerts"
        case .hooks: "Hooks"
        case .notify: "Notify!"
        case .updates: "Updates"
        case .logs: "Logs"
        case .about: "About"
        }
    }

    /// Keywords beyond the title that the settings search matches against.
    var searchKeywords: [String] {
        switch self {
        case .general: ["launch", "login", "overview", "daily usage", "burn rate", "threshold"]
        case .appearance: ["theme", "dark", "light", "cli", "christmas", "import", "color", "contrast", "status", "high contrast"]
        case .menuBar: ["percentage", "duration", "quota display", "stacked", "status bar"]
        case .providers: ["claude", "codex", "gemini", "copilot", "zai", "bedrock", "kimi", "minimax", "enable"]
        case .syncAlerts: ["background", "refresh", "interval", "notification"]
        case .hooks: ["claude code", "session", "install"]
        case .notify: ["iphone", "phone", "lock screen", "live activity", "widget", "gauge", "push", "device"]
        case .updates: ["sparkle", "beta", "version", "check"]
        case .logs: ["log file", "debug", "report"]
        case .about: ["version", "github", "license"]
        }
    }

    /// Sections whose title or keywords match the search filter.
    /// An empty filter matches everything.
    static func matching(filter: String) -> [SettingsSection] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return allCases }
        return allCases.filter { section in
            section.title.lowercased().contains(query)
                || section.searchKeywords.contains { $0.contains(query) }
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .menuBar: "menubar.rectangle"
        case .providers: "cpu"
        case .syncAlerts: "arrow.triangle.2.circlepath"
        case .hooks: "antenna.radiowaves.left.and.right"
        case .notify: "iphone.radiowaves.left.and.right"
        case .updates: "arrow.down.circle.fill"
        case .logs: "doc.text.fill"
        case .about: "info.circle.fill"
        }
    }
}

/// Sidebar groups, in display order.
enum SettingsSectionGroup: String, CaseIterable, Identifiable {
    case app
    case monitoring
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: "App"
        case .monitoring: "Monitoring"
        case .system: "System"
        }
    }

    var sections: [SettingsSection] {
        switch self {
        case .app: [.general, .appearance, .menuBar]
        case .monitoring: [.providers, .syncAlerts, .hooks, .notify]
        case .system: [.updates, .logs, .about]
        }
    }
}
