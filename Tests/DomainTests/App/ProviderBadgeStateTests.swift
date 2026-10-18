import Testing
import Foundation
@testable import Domain

@Suite("ProviderBadgeState Tests")
struct ProviderBadgeStateTests {

    @Test
    func `should show the provider unavailable, not healthy, when it failed before any usage was read`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: nil, hasError: true)

        #expect(state == .unavailable)
        #expect(!state.hasData)
    }

    @Test
    func `should show the provider awaiting data, not healthy, before any usage or failure arrives`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: nil, hasError: false)

        #expect(state == .awaitingData)
        #expect(!state.hasData)
    }

    @Test
    func `should show the provider not set up, not unavailable, when it waits to be set up`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: nil, hasError: true, needsSetup: true)

        #expect(state == .notSetUp)
        #expect(!state.hasData)
    }

    @Test
    func `should say nothing alarming when the provider waits for setup but its usage is read (#198)`() {
        // A Claude Desktop user: no Claude Code, so no limits — but Desktop's
        // tokens today are read. They did set Claude up; NOT SET UP would blame them (#198).
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: nil, hasError: true, needsSetup: true, readsUsage: true)

        #expect(state == .usageOnly)
        #expect(!state.hasData)
    }

    @Test
    func `should keep showing the last quota status when a later setup check failed`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: .healthy, hasError: true, needsSetup: true)

        #expect(state == .quota(.healthy))
    }

    @Test
    func `should show the quota status of the usage it read`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: .warning, hasError: false)

        #expect(state == .quota(.warning))
        #expect(state.hasData)
    }

    @Test
    func `should keep showing the last quota status when a later refresh failed`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: .critical, hasError: true)

        #expect(state == .quota(.critical))
    }

    @Test
    func `should show syncing whatever else the provider's state is`() {
        #expect(ProviderBadgeState(isSyncing: true, quotaStatus: nil, hasError: true) == .syncing)
        #expect(ProviderBadgeState(isSyncing: true, quotaStatus: .healthy, hasError: false) == .syncing)
    }

    // MARK: - A tab of logins

    @MainActor @Test
    func `should show the tab not set up when every login waits for setup`() {
        let state = ProviderBadgeState(of: [Login(needsSetup: true), Login(needsSetup: true)], quotaStatus: nil)
        #expect(state == .notSetUp)
    }

    @MainActor @Test
    func `should show no alarming badge on the tab when a login waiting for setup has its usage read`() {
        let state = ProviderBadgeState(of: [Login(needsSetup: true, readsUsage: true)], quotaStatus: nil)
        #expect(state == .usageOnly)
        #expect(!state.showsBadge)
    }

    @MainActor @Test
    func `should show the tab unavailable, not waiting for setup, when one login really failed`() {
        let state = ProviderBadgeState(of: [Login(needsSetup: true), Login(failed: true)], quotaStatus: nil)
        #expect(state == .unavailable)
        #expect(state.showsBadge)
    }

    @MainActor @Test
    func `should show the tab awaiting data when it has no logins`() {
        #expect(ProviderBadgeState(of: [ProviderBadgeState.Login](), quotaStatus: nil) == .awaitingData)
    }

    @MainActor @Test
    func `should show the tab syncing when one of its logins is syncing`() {
        #expect(ProviderBadgeState(of: [Login(syncing: true), Login(failed: true)], quotaStatus: nil) == .syncing)
    }
}

/// A login as the badge sees it.
private func Login(needsSetup: Bool = false, readsUsage: Bool = false, failed: Bool = false, syncing: Bool = false) -> ProviderBadgeState.Login {
    // A login waiting for setup also carries the error that says so.
    ProviderBadgeState.Login(isSyncing: syncing, failed: needsSetup || failed, needsSetup: needsSetup, readsUsage: readsUsage)
}
