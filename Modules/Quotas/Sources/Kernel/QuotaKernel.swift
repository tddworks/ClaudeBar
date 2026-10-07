@_exported import QuotaKernel
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

// MARK: - The kernel's clock and money

extension Date {
    /// Seconds on the kernel's clock. Apple's reference date keeps a `Date` exact
    /// through the round trip; the kernel only subtracts `now`, so the epoch is ours.
    var kernelSeconds: Double { timeIntervalSinceReferenceDate }

    init(kernelSeconds: Double) { self.init(timeIntervalSinceReferenceDate: kernelSeconds) }
}

enum KernelClock {
    static var now: Double { Date().kernelSeconds }
}

extension Decimal {
    /// Micro-units, the kernel's exact money (1 USD = 1_000_000).
    var micros: Int64 {
        var scaled = self * 1_000_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    init(micros: Int64) { self = Decimal(micros) / 1_000_000 }
}

extension Optional where Wrapped == KotlinDouble {
    var swift: Double? { self?.doubleValue }
}

extension Optional where Wrapped == KotlinLong {
    var swift: Int64? { self?.int64Value }
}

extension Optional where Wrapped == Double {
    var kotlin: KotlinDouble? { map { KotlinDouble(value: $0) } }
}

extension Optional where Wrapped == Int64 {
    var kotlin: KotlinLong? { map { KotlinLong(value: $0) } }
}
