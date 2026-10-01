import Testing
import Foundation
@testable import Domain

@Suite("ProviderBadgeState Tests")
struct ProviderBadgeStateTests {

    @Test
    func `a failed probe with no snapshot is unavailable, not healthy`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: nil, hasError: true)

        #expect(state == .unavailable)
        #expect(!state.hasData)
    }

    @Test
    func `no snapshot and no error yet is awaiting data, not healthy`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: nil, hasError: false)

        #expect(state == .awaitingData)
        #expect(!state.hasData)
    }

    @Test
    func `a snapshot reports its own quota status`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: .warning, hasError: false)

        #expect(state == .quota(.warning))
        #expect(state.hasData)
    }

    @Test
    func `stale numbers still show when a later refresh failed`() {
        let state = ProviderBadgeState(isSyncing: false, quotaStatus: .critical, hasError: true)

        #expect(state == .quota(.critical))
    }

    @Test
    func `syncing wins over every other state`() {
        #expect(ProviderBadgeState(isSyncing: true, quotaStatus: nil, hasError: true) == .syncing)
        #expect(ProviderBadgeState(isSyncing: true, quotaStatus: .healthy, hasError: false) == .syncing)
    }
}
