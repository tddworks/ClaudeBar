import Foundation
import Quotas
import Mockable

/// Where a provider's guest passes come from — Claude reads them from
/// `claude /passes`.
@Mockable
public protocol GuestPassSource: Sendable {
    /// Whether passes can be read here (the CLI exists)
    func isAvailable() async -> Bool

    /// Reads the guest passes
    func fetch() async throws -> GuestPass
}
