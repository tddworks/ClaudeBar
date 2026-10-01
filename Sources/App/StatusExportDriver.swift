import Foundation
import Domain

/// Observes `QuotaMonitor` and `AppSettings` to export the current status to `~/.claudebar/status.json`.
///
/// This provides a zero-latency, offline integration endpoint for external macOS utilities
/// like BetterTouchTool (BTT), MTMR, Raycast, SwiftBar, and terminal scripts.
@MainActor
public final class StatusExportDriver {
    /// Schema of the exported status payload.
    public struct ExportPayload: Codable, Equatable, Sendable {
        public struct ProviderSummary: Codable, Equatable, Sendable {
            public let id: String
            public let name: String
            public let status: String
            public let percentRemaining: Double?
            public let percentUsed: Double?
            public let resetsAt: String?
            public let resetText: String?

            public init(
                id: String,
                name: String,
                status: String,
                percentRemaining: Double? = nil,
                percentUsed: Double? = nil,
                resetsAt: String? = nil,
                resetText: String? = nil
            ) {
                self.id = id
                self.name = name
                self.status = status
                self.percentRemaining = percentRemaining
                self.percentUsed = percentUsed
                self.resetsAt = resetsAt
                self.resetText = resetText
            }
        }

        public let enabled: Bool
        public var updatedAt: String
        public let menuBarText: String
        public let status: String
        public let selectedProviderId: String
        public let selectedProviderName: String?
        public let providers: [ProviderSummary]

        public init(
            enabled: Bool = true,
            updatedAt: String,
            menuBarText: String,
            status: String,
            selectedProviderId: String,
            selectedProviderName: String?,
            providers: [ProviderSummary]
        ) {
            self.enabled = enabled
            self.updatedAt = updatedAt
            self.menuBarText = menuBarText
            self.status = status
            self.selectedProviderId = selectedProviderId
            self.selectedProviderName = selectedProviderName
            self.providers = providers
        }

        public static func == (lhs: ExportPayload, rhs: ExportPayload) -> Bool {
            lhs.enabled == rhs.enabled &&
            lhs.menuBarText == rhs.menuBarText &&
            lhs.status == rhs.status &&
            lhs.selectedProviderId == rhs.selectedProviderId &&
            lhs.selectedProviderName == rhs.selectedProviderName &&
            lhs.providers == rhs.providers
        }
    }

    private let monitor: QuotaMonitor
    private let settings: AppSettings
    private let fileURL: URL
    private var sync: ObservationRenderSync<ExportPayload>?

    public init(
        monitor: QuotaMonitor,
        settings: AppSettings,
        fileURL: URL? = nil
    ) {
        self.monitor = monitor
        self.settings = settings
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = home.appendingPathComponent(".claudebar/status.json")
        }
    }

    /// Starts observing state changes and writes the initial payload.
    public func start() {
        guard sync == nil else { return }
        let newSync = ObservationRenderSync(
            read: { [self] in buildPayload() },
            render: { [self] payload in writePayload(payload) }
        )
        sync = newSync
        newSync.start()
    }

    /// Stops observing state changes.
    public func stop() {
        sync?.stop()
        sync = nil
    }

    private func buildPayload() -> ExportPayload {
        guard settings.touchBarEnabled else {
            return ExportPayload(
                enabled: false,
                updatedAt: "",
                menuBarText: "",
                status: "disabled",
                selectedProviderId: "",
                selectedProviderName: nil,
                providers: []
            )
        }

        let label = monitor.menuBarLabel(
            providerId: settings.menuBarPercentageProviderId,
            primaryQuotaKey: settings.menuBarPercentageQuotaKey,
            secondaryQuotaKey: settings.menuBarSecondaryQuotaKey,
            showPercentage: settings.menuBarPercentageEnabled,
            showDuration: settings.menuBarDurationEnabled,
            mode: settings.usageDisplayMode,
            burnRateWarningEnabled: settings.burnRateWarningEnabled,
            burnRateThreshold: settings.burnRateThreshold
        )

        let selected = monitor.selectedProvider
        let statusString: String
        if let labelStatus = label?.status {
            statusString = statusName(labelStatus)
        } else if let selectedStatus = selected?.snapshot?.overallStatus {
            statusString = statusName(selectedStatus)
        } else {
            statusString = "unknown"
        }

        let isoFormatter = ISO8601DateFormatter()
        let providers = monitor.enabledProviders.map { provider in
            let snapshot = provider.snapshot
            let primary = snapshot?.quotas.first ?? snapshot?.lowestQuota
            return ExportPayload.ProviderSummary(
                id: provider.id,
                name: provider.name,
                status: statusName(snapshot?.overallStatus ?? .healthy),
                percentRemaining: primary?.percentRemaining,
                percentUsed: primary?.percentUsed,
                resetsAt: primary?.resetsAt.map { isoFormatter.string(from: $0) },
                resetText: primary?.resetText
            )
        }

        return ExportPayload(
            enabled: true,
            updatedAt: "",
            menuBarText: label?.text ?? selected?.name ?? "ClaudeBar",
            status: statusString,
            selectedProviderId: monitor.selectedProviderId,
            selectedProviderName: selected?.name,
            providers: providers
        )
    }

    private func statusName(_ status: QuotaStatus) -> String {
        switch status {
        case .healthy: return "healthy"
        case .warning: return "warning"
        case .critical: return "critical"
        case .depleted: return "depleted"
        }
    }

    private func writePayload(_ payload: ExportPayload) {
        var finalPayload = payload
        finalPayload.updatedAt = ISO8601DateFormatter().string(from: Date())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(finalPayload) else { return }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let tempURL = dir.appendingPathComponent(".status.tmp.\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } catch {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
