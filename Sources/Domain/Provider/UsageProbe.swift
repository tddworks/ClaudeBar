import Quotas
import DataSources
import Foundation
import Mockable
import Providers

/// Protocol defining how to probe for usage data.
/// This is an internal implementation detail - callers use AIProvider.refresh() instead.
@Mockable
public protocol UsageProbe: Sendable {
    /// Fetches the current usage snapshot
    func probe() async throws -> UsageSnapshot

    /// Checks if the probe is available (CLI installed, credentials present, etc.)
    func isAvailable() async -> Bool
}
