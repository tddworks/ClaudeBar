import Testing
import Foundation
@testable import Domain

@Suite("Usage Snapshot Tests")
struct UsageSnapshotTests {

    // MARK: - Snapshot Creation

    @Test("Creates snapshot with single quota")
    func createSnapshotWithSingleQuota() {
        let quota = UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude)
        let snapshot = UsageSnapshot(
            provider: .claude,
            quotas: [quota],
            capturedAt: Date()
        )

        #expect(snapshot.provider == .claude)
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 65)
    }

    @Test("Creates snapshot with multiple quotas")
    func createSnapshotWithMultipleQuotas() {
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude)
        let weeklyQuota = UsageQuota(percentRemaining: 35, quotaType: .weekly, provider: .claude)
        let opusQuota = UsageQuota(percentRemaining: 80, quotaType: .modelSpecific("opus"), provider: .claude)

        let snapshot = UsageSnapshot(
            provider: .claude,
            quotas: [sessionQuota, weeklyQuota, opusQuota],
            capturedAt: Date()
        )

        #expect(snapshot.quotas.count == 3)
    }

    // MARK: - Snapshot Queries

    @Test("Finds session quota from snapshot")
    func findSessionQuota() {
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude)
        let weeklyQuota = UsageQuota(percentRemaining: 35, quotaType: .weekly, provider: .claude)
        let snapshot = UsageSnapshot(provider: .claude, quotas: [sessionQuota, weeklyQuota], capturedAt: Date())

        let found = snapshot.quota(for: .session)

        #expect(found?.percentRemaining == 65)
    }

    @Test("Finds weekly quota from snapshot")
    func findWeeklyQuota() {
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude)
        let weeklyQuota = UsageQuota(percentRemaining: 35, quotaType: .weekly, provider: .claude)
        let snapshot = UsageSnapshot(provider: .claude, quotas: [sessionQuota, weeklyQuota], capturedAt: Date())

        let found = snapshot.quota(for: .weekly)

        #expect(found?.percentRemaining == 35)
    }

    @Test("Returns nil when quota type not found")
    func returnsNilWhenQuotaNotFound() {
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, provider: .claude)
        let snapshot = UsageSnapshot(provider: .claude, quotas: [sessionQuota], capturedAt: Date())

        let found = snapshot.quota(for: .weekly)

        #expect(found == nil)
    }

    // MARK: - Overall Status

    @Test("Overall status is healthy when all quotas healthy")
    func overallStatusHealthyWhenAllHealthy() {
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, provider: .claude),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, provider: .claude),
        ]
        let snapshot = UsageSnapshot(provider: .claude, quotas: quotas, capturedAt: Date())

        #expect(snapshot.overallStatus == .healthy)
    }

    @Test("Overall status is warning when any quota is warning")
    func overallStatusWarningWhenAnyWarning() {
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, provider: .claude),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, provider: .claude),
        ]
        let snapshot = UsageSnapshot(provider: .claude, quotas: quotas, capturedAt: Date())

        #expect(snapshot.overallStatus == .warning)
    }

    @Test("Overall status is critical when any quota is critical")
    func overallStatusCriticalWhenAnyCritical() {
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, provider: .claude),
            UsageQuota(percentRemaining: 15, quotaType: .weekly, provider: .claude),
        ]
        let snapshot = UsageSnapshot(provider: .claude, quotas: quotas, capturedAt: Date())

        #expect(snapshot.overallStatus == .critical)
    }

    @Test("Overall status is depleted when any quota is depleted")
    func overallStatusDepletedWhenAnyDepleted() {
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, provider: .claude),
            UsageQuota(percentRemaining: 0, quotaType: .weekly, provider: .claude),
        ]
        let snapshot = UsageSnapshot(provider: .claude, quotas: quotas, capturedAt: Date())

        #expect(snapshot.overallStatus == .depleted)
    }

    // MARK: - Snapshot Age

    @Test("Snapshot knows its age")
    func snapshotKnowsAge() {
        let capturedAt = Date().addingTimeInterval(-120) // 2 minutes ago
        let snapshot = UsageSnapshot(provider: .claude, quotas: [], capturedAt: capturedAt)

        let ageInSeconds = snapshot.age
        #expect(ageInSeconds >= 119 && ageInSeconds <= 121) // Allow small margin
    }

    @Test("Snapshot is stale after 5 minutes")
    func snapshotIsStaleAfter5Minutes() {
        let capturedAt = Date().addingTimeInterval(-360) // 6 minutes ago
        let snapshot = UsageSnapshot(provider: .claude, quotas: [], capturedAt: capturedAt)

        #expect(snapshot.isStale == true)
    }

    @Test("Snapshot is fresh within 5 minutes")
    func snapshotIsFreshWithin5Minutes() {
        let capturedAt = Date().addingTimeInterval(-60) // 1 minute ago
        let snapshot = UsageSnapshot(provider: .claude, quotas: [], capturedAt: capturedAt)

        #expect(snapshot.isStale == false)
    }

    // MARK: - Lowest Quota

    @Test("Returns lowest quota from snapshot")
    func returnsLowestQuota() {
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, provider: .claude),
            UsageQuota(percentRemaining: 25, quotaType: .weekly, provider: .claude),
            UsageQuota(percentRemaining: 60, quotaType: .modelSpecific("opus"), provider: .claude),
        ]
        let snapshot = UsageSnapshot(provider: .claude, quotas: quotas, capturedAt: Date())

        let lowest = snapshot.lowestQuota

        #expect(lowest?.percentRemaining == 25)
        #expect(lowest?.quotaType == .weekly)
    }
}
