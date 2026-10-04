import Quotas
import Foundation
import Observation

/// *Share Claude Code* — a provider's guest passes: invitation links its plan
/// lets the person hand out. An action, not usage, so it lives beside the
/// provider's usage and never touches `lastError`.
@MainActor
@Observable
public final class GuestPasses {
    public private(set) var pass: GuestPass?
    public private(set) var isFetching = false
    /// Separate from the provider's `lastError`: a failed pass fetch never
    /// marks usage unavailable.
    public private(set) var error: Error?

    private let source: any GuestPassSource

    public init(source: any GuestPassSource) {
        self.source = source
    }

    /// Offered only to a plan that can issue passes (#243).
    public func isOffered(for usage: UsageSnapshot?) -> Bool {
        usage?.accountTier?.supportsGuestPasses == true
    }

    @discardableResult
    public func fetch() async throws -> GuestPass {
        isFetching = true
        defer { isFetching = false }
        do {
            let pass = try await source.fetch()
            self.pass = pass
            error = nil
            return pass
        } catch {
            self.error = error
            throw error
        }
    }

    public func clearError() {
        error = nil
    }
}
