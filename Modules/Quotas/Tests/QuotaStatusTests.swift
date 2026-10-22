import Testing
import Foundation
@testable import Quotas

@Suite
struct QuotaStatusTests {

    // MARK: - Factory Method Tests

    @Test
    func `should call a quota healthy when 50 percent or more is left`() {
        #expect(QuotaStatus.from(percentRemaining: 100) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 75) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 51) == .healthy)
        #expect(QuotaStatus.from(percentRemaining: 50) == .healthy)
    }

    @Test
    func `should warn when between 20 and 49 percent is left`() {
        #expect(QuotaStatus.from(percentRemaining: 49) == .warning)
        #expect(QuotaStatus.from(percentRemaining: 35) == .warning)
        #expect(QuotaStatus.from(percentRemaining: 20) == .warning)
    }

    @Test
    func `should call a quota critical when between 1 and 19 percent is left`() {
        #expect(QuotaStatus.from(percentRemaining: 19) == .critical)
        #expect(QuotaStatus.from(percentRemaining: 10) == .critical)
        #expect(QuotaStatus.from(percentRemaining: 1) == .critical)
    }

    @Test
    func `should call a quota depleted when nothing or less is left`() {
        #expect(QuotaStatus.from(percentRemaining: 0) == .depleted)
        #expect(QuotaStatus.from(percentRemaining: -1) == .depleted)
        #expect(QuotaStatus.from(percentRemaining: -100) == .depleted)
    }

    // MARK: - Needs Attention Tests

    @Test
    func `should not ask for attention when a quota is healthy`() {
        #expect(QuotaStatus.healthy.needsAttention == false)
    }

    @Test
    func `should ask for attention when a quota is in warning`() {
        #expect(QuotaStatus.warning.needsAttention == true)
    }

    @Test
    func `should ask for attention when a quota is critical`() {
        #expect(QuotaStatus.critical.needsAttention == true)
    }

    @Test
    func `should ask for attention when a quota is depleted`() {
        #expect(QuotaStatus.depleted.needsAttention == true)
    }

    // MARK: - Comparison Tests (Severity Order)

    @Test
    func `should rank healthy as less severe than warning`() {
        #expect(QuotaStatus.healthy < QuotaStatus.warning)
    }

    @Test
    func `should rank warning as less severe than critical`() {
        #expect(QuotaStatus.warning < QuotaStatus.critical)
    }

    @Test
    func `should rank critical as less severe than depleted`() {
        #expect(QuotaStatus.critical < QuotaStatus.depleted)
    }

    @Test
    func `should rank depleted as the most severe status`() {
        #expect(QuotaStatus.depleted > QuotaStatus.healthy)
        #expect(QuotaStatus.depleted > QuotaStatus.warning)
        #expect(QuotaStatus.depleted > QuotaStatus.critical)
    }

    @Test
    func `should pick the worst of several statuses`() {
        let statuses: [QuotaStatus] = [.healthy, .warning, .critical]
        #expect(statuses.max() == .critical)

        let mixedStatuses: [QuotaStatus] = [.warning, .depleted, .healthy]
        #expect(mixedStatuses.max() == .depleted)
    }

    // MARK: - Equality Tests

    @Test
    func `should treat each status as equal to itself`() {
        #expect(QuotaStatus.healthy == .healthy)
        #expect(QuotaStatus.warning == .warning)
        #expect(QuotaStatus.critical == .critical)
        #expect(QuotaStatus.depleted == .depleted)
    }

    @Test
    func `should tell different statuses apart`() {
        #expect(QuotaStatus.healthy != .warning)
        #expect(QuotaStatus.warning != .critical)
        #expect(QuotaStatus.critical != .depleted)
    }

    // MARK: - Hashable Tests

    @Test
    func `should let each status carry its own color in a lookup`() {
        var dict: [QuotaStatus: String] = [:]
        dict[.healthy] = "green"
        dict[.warning] = "yellow"

        #expect(dict[.healthy] == "green")
        #expect(dict[.warning] == "yellow")
    }

    @Test
    func `should count a repeated status once in a set of statuses`() {
        let statuses: Set<QuotaStatus> = [.healthy, .warning, .healthy]
        #expect(statuses.count == 2)
    }
}
