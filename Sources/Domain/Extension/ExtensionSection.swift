import Quotas
import DataSources
import Providers
import Foundation

/// Defines a single section within an extension, with its own probe config and refresh interval.
public struct ExtensionSection: Sendable, Equatable {
    public let id: String
    public let type: SectionType
    public let probeConfig: ProbeConfig
    public let refreshInterval: TimeInterval
    public let timeout: TimeInterval

    /// Convenience accessor for script command (nil for built-in probes)
    public var probeCommand: String {
        switch probeConfig {
        case .script(let command): return command
        case .healthCheck: return ""
        }
    }

    public init(
        id: String,
        type: SectionType,
        probeCommand: String,
        refreshInterval: TimeInterval = 60,
        timeout: TimeInterval = 10
    ) {
        self.id = id
        self.type = type
        self.probeConfig = .script(probeCommand)
        self.refreshInterval = refreshInterval
        self.timeout = timeout
    }

    public init(
        id: String,
        type: SectionType,
        probeConfig: ProbeConfig,
        refreshInterval: TimeInterval = 60,
        timeout: TimeInterval = 10
    ) {
        self.id = id
        self.type = type
        self.probeConfig = probeConfig
        self.refreshInterval = refreshInterval
        self.timeout = timeout
    }
}

/// How a section acquires its data.
public enum ProbeConfig: Sendable, Equatable {
    /// External script that outputs JSON to stdout
    case script(String)
    /// Built-in health check that pings a URL
    case healthCheck(url: URL)
}

/// The type of UI section an extension section renders as.
public enum SectionType: String, Sendable, Equatable {
    /// Quota cards with percentage bars (SESSION, WEEKLY, etc.)
    case quotaGrid
    /// Cost-based usage card
    case costUsage
    /// Daily usage comparison cards (cost, tokens, working time)
    case dailyUsage
    /// Generic metric cards with values, units, and deltas
    case metricsRow
    /// Simple status banner (e.g., "Active", "Connected")
    case statusBanner
    /// Built-in health check (ping URL, show latency + status)
    case healthCheck
}
