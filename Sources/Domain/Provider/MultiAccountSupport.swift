import Quotas
import DataSources
import Providers
import Foundation

/// Protocol for providers that support multiple accounts.
///
/// Single-account providers don't need to implement this — they work as before.
/// Multi-account providers implement this to expose their account list and
/// allow adding/removing accounts at runtime.
///
/// Design rationale: This is an opt-in protocol rather than a change to `AIProvider`.
/// Existing providers continue to work unchanged. The `QuotaMonitor` checks for
/// conformance and adapts its behavior accordingly.
///
/// Note: @Mockable is intentionally omitted here. The macro cannot generate stubs
/// for inherited protocol requirements (Mockable#128). When tests need a mock,
/// use the aggregate-protocol pattern recommended by the Mockable maintainer:
/// create a flat @Mockable protocol in the test target that re-declares all
/// requirements from both AIProvider and MultiAccountProvider.
public protocol MultiAccountProvider: AIProvider {
    /// All accounts registered for this provider
    var accounts: [ProviderAccount] { get }

    /// The currently active account (whose snapshot is exposed via `snapshot`)
    var activeAccount: ProviderAccount { get }

    /// Snapshots for all accounts (keyed by account ID)
    var accountSnapshots: [String: UsageSnapshot] { get }

    /// Switches the active account.
    /// After switching, `snapshot` reflects the new active account's data.
    /// - Parameter accountId: The account ID to switch to
    /// - Returns: true if the switch succeeded (account exists)
    @discardableResult
    func switchAccount(to accountId: String) -> Bool

    /// Refreshes a specific account's usage data.
    /// - Parameter accountId: The account to refresh
    /// - Returns: The updated snapshot
    @discardableResult
    func refreshAccount(_ accountId: String) async throws -> UsageSnapshot

    /// Refreshes all accounts concurrently.
    func refreshAllAccounts() async

    /// The aggregate status across all accounts (worst status wins).
    var aggregateStatus: QuotaStatus { get }

    /// The account with the most remaining quota (best candidate for use).
    var bestAvailableAccount: ProviderAccount? { get }
}

// MARK: - Default Implementations

public extension MultiAccountProvider {
    /// Default: aggregate status is the worst across all account snapshots
    var aggregateStatus: QuotaStatus {
        accountSnapshots.values
            .map(\.overallStatus)
            .max() ?? .healthy
    }

    /// Default: the account with the highest remaining quota percentage
    var bestAvailableAccount: ProviderAccount? {
        let sorted = accounts.compactMap { account -> (ProviderAccount, Double)? in
            guard let snapshot = accountSnapshots[account.accountId],
                  let lowest = snapshot.lowestQuota else {
                return nil
            }
            return (account, lowest.percentRemaining)
        }
        .sorted { $0.1 > $1.1 }

        return sorted.first?.0
    }
}

// MARK: - AIProviderRepository Extension

public extension AIProviderRepository {
    /// Returns all providers that support multiple accounts
    var multiAccountProviders: [any MultiAccountProvider] {
        all.compactMap { $0 as? (any MultiAccountProvider) }
    }

    /// Finds a multi-account provider by its ID
    func multiAccountProvider(id: String) -> (any MultiAccountProvider)? {
        provider(id: id) as? (any MultiAccountProvider)
    }

    /// Total number of accounts across all multi-account providers
    var totalAccountCount: Int {
        all.reduce(0) { count, provider in
            if let multi = provider as? (any MultiAccountProvider) {
                return count + multi.accounts.count
            }
            return count + 1 // Single-account providers count as 1
        }
    }
}
