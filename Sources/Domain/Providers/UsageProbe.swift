import Quotas
import DataSources
import Foundation
import Mockable
import Providers

/// What a test's stubbed login answers with (`stubbedLogin` in the test
/// targets): the usage, or whether it is ready. The app never uses it — a
/// login's usage comes from its provider's data sources.
@Mockable
public protocol UsageProbe: Sendable {
    /// Fetches the current usage snapshot
    func probe() async throws -> UsageSnapshot

    /// Checks if the probe is available (CLI installed, credentials present, etc.)
    func isAvailable() async -> Bool
}
