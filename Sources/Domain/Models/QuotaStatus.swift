import Foundation

/// Represents the health status of a usage quota.
/// Rich domain model - status is determined by business rules, not UI logic.
public enum QuotaStatus: Sendable, Equatable, Hashable, Comparable {
    /// Quota has remaining capacity (>50%)
    case healthy
    /// Quota is getting low (20-50%)
    case warning
    /// Quota is almost exhausted (<20%)
    case critical
    /// Quota is completely exhausted (0%)
    case depleted

    // MARK: - Factory Methods

    /// Creates a status based on the percentage remaining.
    /// This encapsulates the business rules for status thresholds.
    public static func from(percentRemaining: Double) -> QuotaStatus {
        switch percentRemaining {
        case ...0:
            .depleted
        case 0..<20:
            .critical
        case 20..<50:
            .warning
        default:
            .healthy
        }
    }

    // MARK: - Status Behavior

    /// Whether this status indicates a problem that needs attention
    public var needsAttention: Bool {
        switch self {
        case .healthy:
            false
        case .warning, .critical, .depleted:
            true
        }
    }

    /// The severity level (higher = more severe)
    private var severity: Int {
        switch self {
        case .healthy: 0
        case .warning: 1
        case .critical: 2
        case .depleted: 3
        }
    }

    public static func < (lhs: QuotaStatus, rhs: QuotaStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

extension QuotaStatus {
    /// The color to display for this status
    public var displayColor: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .critical, .depleted: .red
        }
    }
}
