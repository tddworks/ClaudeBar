import Quotas
import DataSources
import Providers
import Foundation

/// Result of a built-in health check ping against a URL endpoint.
/// Rich domain model with computed status, formatting, and conversion to metrics.
public struct HealthCheckResult: Sendable, Equatable {
    public let url: URL
    public let statusCode: Int
    public let latencyMs: Int
    public let checkedAt: Date

    public init(url: URL, statusCode: Int, latencyMs: Int, checkedAt: Date) {
        self.url = url
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.checkedAt = checkedAt
    }

    // MARK: - Domain Behavior

    /// Whether the endpoint is considered up (2xx response)
    public var isUp: Bool {
        (200...299).contains(statusCode)
    }

    /// Overall health status based on response code and latency
    public var status: StatusLevel {
        if statusCode == 0 || (500...599).contains(statusCode) {
            return .critical
        }
        if (400...499).contains(statusCode) {
            return .warning
        }
        // 2xx but slow (>2000ms)
        if latencyMs > 2000 {
            return .warning
        }
        return .healthy
    }

    /// "UP" or "DOWN"
    public var statusText: String {
        isUp ? "UP" : "DOWN"
    }

    /// Human-readable status code (e.g., "200 OK", "500 Server Error")
    public var statusCodeText: String {
        switch statusCode {
        case 0: return "No Response"
        case 200...299: return "\(statusCode) OK"
        case 400...499: return "\(statusCode) Client Error"
        case 500...599: return "\(statusCode) Server Error"
        default: return "\(statusCode)"
        }
    }

    /// Formatted latency (e.g., "142ms", "5.2s")
    public var formattedLatency: String {
        if latencyMs >= 1000 {
            return String(format: "%.1fs", Double(latencyMs) / 1000.0)
        }
        return "\(latencyMs)ms"
    }

    /// Converts to ExtensionMetric array for rendering in the metrics card grid.
    public func toExtensionMetrics() -> [ExtensionMetric] {
        let statusColor = switch status {
        case .healthy: "#4CAF50"
        case .warning: "#FF9800"
        case .critical: "#F44336"
        case .inactive: "#9E9E9E"
        }

        return [
            ExtensionMetric(
                label: "Status",
                value: statusText,
                unit: statusCodeText,
                icon: isUp ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: statusColor
            ),
            ExtensionMetric(
                label: "Latency",
                value: formattedLatency,
                unit: url.host ?? url.absoluteString,
                icon: "network",
                color: latencyMs > 2000 ? "#FF9800" : "#2196F3",
                progress: min(1.0, Double(latencyMs) / 3000.0)
            ),
        ]
    }
}
