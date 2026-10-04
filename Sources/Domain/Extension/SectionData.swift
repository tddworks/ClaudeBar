import Quotas
import DataSources
import Providers
import Foundation

/// Represents parsed probe output data for a specific section type.
/// Maps JSON output from probe scripts into existing domain models.
public enum SectionData: Sendable, Equatable {
    /// Quota grid data — reuses existing UsageQuota model
    case quotas([UsageQuota])
    /// Cost usage data — reuses existing CostUsage model
    case cost(CostUsage)
    /// Daily usage comparison — reuses existing DailyUsageReport model
    case daily(DailyUsageReport)
    /// Generic metrics — new ExtensionMetric model
    case metrics([ExtensionMetric])
    /// Status banner — simple text + level
    case status(StatusInfo)

    /// Decodes probe script JSON output into the appropriate SectionData case.
    public static func decode(from data: Data, type: SectionType, providerId: String) throws -> SectionData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch type {
        case .quotaGrid:
            let raw = try decoder.decode(RawQuotaOutput.self, from: data)
            guard let rawQuotas = raw.quotas else {
                throw SectionDataError.missingKey("quotas")
            }
            let quotas = rawQuotas.map { $0.toUsageQuota(providerId: providerId) }
            return .quotas(quotas)

        case .costUsage:
            let raw = try decoder.decode(RawCostOutput.self, from: data)
            guard let rawCost = raw.costUsage else {
                throw SectionDataError.missingKey("costUsage")
            }
            return .cost(rawCost.toCostUsage(providerId: providerId))

        case .dailyUsage:
            let raw = try decoder.decode(RawDailyOutput.self, from: data)
            guard let rawDaily = raw.dailyUsage else {
                throw SectionDataError.missingKey("dailyUsage")
            }
            return .daily(rawDaily.toDailyUsageReport())

        case .metricsRow:
            let raw = try decoder.decode(RawMetricsOutput.self, from: data)
            guard let metrics = raw.metrics else {
                throw SectionDataError.missingKey("metrics")
            }
            return .metrics(metrics)

        case .statusBanner:
            let raw = try decoder.decode(RawStatusOutput.self, from: data)
            guard let status = raw.status else {
                throw SectionDataError.missingKey("status")
            }
            return .status(status)

        case .healthCheck:
            // Health check data is produced by HealthCheckProbe directly, not from script JSON.
            // This case should not be reached via SectionData.decode().
            throw SectionDataError.missingKey("healthCheck (built-in probe, not script-based)")
        }
    }
}

public enum SectionDataError: Error, LocalizedError {
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey(let key):
            "Probe output missing required key: '\(key)'"
        }
    }
}

// MARK: - Raw JSON Types for Decoding

private struct RawQuotaOutput: Codable {
    let quotas: [RawQuota]?
}

private struct RawQuota: Codable {
    let type: String
    let percentRemaining: Double
    let resetsAt: Date?
    let resetText: String?
    let dollarRemaining: Double?

    func toUsageQuota(providerId: String) -> UsageQuota {
        let quotaType: QuotaType = switch type {
        case "session": .session
        case "weekly": .weekly
        case let t where t.hasPrefix("model:"):
            .modelSpecific(String(t.dropFirst(6)))
        default:
            .timeLimit(type)
        }

        return UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: quotaType,
            providerId: providerId,
            resetsAt: resetsAt,
            resetText: resetText,
            windowDuration: quotaType.conventionalWindow.seconds,
            dollarRemaining: dollarRemaining.map { Decimal($0) }
        )
    }
}

private struct RawCostOutput: Codable {
    let costUsage: RawCostUsage?
}

private struct RawCostUsage: Codable {
    let totalCost: Double
    let budget: Double?
    let apiDuration: TimeInterval
    let wallDuration: TimeInterval?
    let linesAdded: Int?
    let linesRemoved: Int?

    func toCostUsage(providerId: String) -> CostUsage {
        CostUsage(
            totalCost: Decimal(totalCost),
            budget: budget.map { Decimal($0) },
            apiDuration: apiDuration,
            wallDuration: wallDuration ?? 0,
            linesAdded: linesAdded ?? 0,
            linesRemoved: linesRemoved ?? 0,
            providerId: providerId
        )
    }
}

private struct RawDailyOutput: Codable {
    let dailyUsage: RawDailyUsage?
}

private struct RawDailyUsage: Codable {
    let today: RawDailyStat
    let previous: RawDailyStat

    func toDailyUsageReport() -> DailyUsageReport {
        DailyUsageReport(
            today: today.toDailyUsageStat(),
            previous: previous.toDailyUsageStat()
        )
    }
}

private struct RawDailyStat: Codable {
    let totalCost: Double
    let totalTokens: Int
    let workingTime: TimeInterval
    let date: String
    let sessionCount: Int?

    func toDailyUsageStat() -> DailyUsageStat {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let parsedDate = dateFormatter.date(from: date) ?? Date()

        return DailyUsageStat(
            date: parsedDate,
            totalCost: Decimal(totalCost),
            totalTokens: totalTokens,
            workingTime: workingTime,
            sessionCount: sessionCount ?? 0
        )
    }
}

private struct RawMetricsOutput: Codable {
    let metrics: [ExtensionMetric]?
}

private struct RawStatusOutput: Codable {
    let status: StatusInfo?
}
