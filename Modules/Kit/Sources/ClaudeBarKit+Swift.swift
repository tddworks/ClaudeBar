@_exported import ClaudeBarKit
import Foundation

// The Swift face of the Kotlin kernel (docs/architecture/MODULAR_DESIGN.md §3.1).
// Only this folder names the bridge: SKIE's types, KotlinDouble/KotlinLong boxes,
// and the kernel's seconds and micro-units. Everything else speaks Date and Decimal.

// MARK: - Sendable
//
// Kotlin owns these values and their concurrency: each is immutable, and Kotlin/Native
// objects are safe to share across threads. SKIE already marks the kernel's enums.

extension UsageQuota: @retroactive @unchecked Sendable {}
extension QuotaType: @retroactive @unchecked Sendable {}
extension QuotaDuration: @retroactive @unchecked Sendable {}
extension StatusPolicy: @retroactive @unchecked Sendable {}
extension Left: @retroactive @unchecked Sendable {}
extension Money: @retroactive @unchecked Sendable {}
extension Window: @retroactive @unchecked Sendable {}
extension UsageSnapshot: @retroactive @unchecked Sendable {}
extension QuotaGroup: @retroactive @unchecked Sendable {}
extension AccountTier: @retroactive @unchecked Sendable {}
extension CostUsage: @retroactive @unchecked Sendable {}
extension CostLine: @retroactive @unchecked Sendable {}
extension DailyUsageStat: @retroactive @unchecked Sendable {}
extension DailyUsageReport: @retroactive @unchecked Sendable {}
extension ExtensionMetric: @retroactive @unchecked Sendable {}
extension MetricDelta: @retroactive @unchecked Sendable {}

// MARK: - The kernel's clock and money

extension Date {
    /// Seconds on the SDK's clock: since 1970 (Unix), the one epoch every platform shares.
    var kernelSeconds: Double { timeIntervalSince1970 }

    init(kernelSeconds: Double) { self.init(timeIntervalSince1970: kernelSeconds) }
}

enum KernelClock {
    static var now: Double { Date().kernelSeconds }
}

extension Decimal {
    /// Nano-units, the kernel's exact money (1 USD = 1_000_000_000).
    var nanos: Int64 {
        var scaled = self * 1_000_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    init(nanos: Int64) { self = Decimal(nanos) / 1_000_000_000 }
}

extension Optional where Wrapped == KotlinDouble {
    var swift: Double? { self?.doubleValue }
}

extension Optional where Wrapped == KotlinLong {
    var swift: Int64? { self?.int64Value }
}

/// Dollars the way the cards print them ("$14.26").
func formattedUSD(_ amount: Decimal, locale: String = "en_US_POSIX") -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.locale = Locale(identifier: locale)
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
}

/// A count the way the cards print it ("19.5M", "1.2K", "500").
func formattedCount(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000.0) }
    if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000.0) }
    return "\(count)"
}

extension Optional where Wrapped == Double {
    var kotlin: KotlinDouble? { map { KotlinDouble(value: $0) } }
}

extension Optional where Wrapped == Int64 {
    var kotlin: KotlinLong? { map { KotlinLong(value: $0) } }
}
