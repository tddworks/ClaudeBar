import Testing
import Foundation
@testable import Domain

@Suite(.serialized)
struct UsageSnapshotTests {

    // MARK: - Creating Snapshots

    @Test
    func `snapshot captures quotas for a provider`() {
        // Given
        let quota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")

        // When
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [quota], capturedAt: Date())

        // Then
        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.count == 1)
        #expect(snapshot.quotas.first?.percentRemaining == 65)
    }

    @Test
    func `snapshot can hold multiple quota types`() {
        // Given
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")
        let weeklyQuota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
        let opusQuota = UsageQuota(percentRemaining: 80, quotaType: .modelSpecific("opus"), providerId: "claude")

        // When
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [sessionQuota, weeklyQuota, opusQuota],
            capturedAt: Date()
        )

        // Then
        #expect(snapshot.quotas.count == 3)
    }

    // MARK: - Finding Quotas

    @Test
    func `snapshot can find session quota by type`() {
        // Given
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")
        let weeklyQuota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [sessionQuota, weeklyQuota], capturedAt: Date())

        // When
        let found = snapshot.quota(for: .session)

        // Then
        #expect(found?.percentRemaining == 65)
    }

    @Test
    func `snapshot can find weekly quota by type`() {
        // Given
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")
        let weeklyQuota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [sessionQuota, weeklyQuota], capturedAt: Date())

        // When
        let found = snapshot.quota(for: .weekly)

        // Then
        #expect(found?.percentRemaining == 35)
    }

    @Test
    func `snapshot returns nil when quota type not found`() {
        // Given
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [sessionQuota], capturedAt: Date())

        // When
        let found = snapshot.quota(for: .weekly)

        // Then
        #expect(found == nil)
    }

    @Test
    func `quota types round trip persisted quota keys`() {
        #expect(QuotaType(quotaKey: QuotaType.session.quotaKey) == .session)
        #expect(QuotaType(quotaKey: QuotaType.weekly.quotaKey) == .weekly)
        #expect(QuotaType(quotaKey: QuotaType.modelSpecific("opus").quotaKey) == .modelSpecific("opus"))
        #expect(QuotaType(quotaKey: QuotaType.timeLimit("mcp").quotaKey) == .timeLimit("mcp"))
        #expect(QuotaType(quotaKey: "model:") == nil)
        #expect(QuotaType(quotaKey: "unknown") == nil)
    }

    @Test
    func `snapshot can find dynamic quota by persisted key`() {
        // Given
        let opusQuota = UsageQuota(percentRemaining: 80, quotaType: .modelSpecific("opus"), providerId: "claude")
        let mcpQuota = UsageQuota(percentRemaining: 40, quotaType: .timeLimit("mcp"), providerId: "claude")
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [opusQuota, mcpQuota],
            capturedAt: Date()
        )

        // When
        let foundModel = snapshot.quota(forKey: "model:opus")
        let foundTimeLimit = snapshot.quota(forKey: "time:mcp")

        // Then
        #expect(foundModel?.percentRemaining == 80)
        #expect(foundTimeLimit?.percentRemaining == 40)
    }

    // MARK: - Overall Status

    @Test
    func `overall status is healthy when all quotas are healthy`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When & Then
        #expect(snapshot.overallStatus == .healthy)
    }

    @Test
    func `overall status reflects worst quota when one is warning`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When & Then
        #expect(snapshot.overallStatus == .warning)
    }

    @Test
    func `overall status reflects worst quota when one is critical`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 15, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When & Then
        #expect(snapshot.overallStatus == .critical)
    }

    @Test
    func `overall status is depleted when any quota is depleted`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 0, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When & Then
        #expect(snapshot.overallStatus == .depleted)
    }

    // MARK: - Freshness

    @Test
    func `snapshot knows how old it is`() {
        // Given
        let capturedAt = Date().addingTimeInterval(-120) // 2 minutes ago
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: capturedAt)

        // When
        let ageInSeconds = snapshot.age

        // Then
        #expect(ageInSeconds >= 119 && ageInSeconds <= 121)
    }

    @Test
    func `snapshot is stale after 5 minutes`() {
        // Given
        let capturedAt = Date().addingTimeInterval(-360) // 6 minutes ago
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: capturedAt)

        // When & Then
        #expect(snapshot.isStale == true)
    }

    @Test
    func `snapshot is fresh within 5 minutes`() {
        // Given
        let capturedAt = Date().addingTimeInterval(-60) // 1 minute ago
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: capturedAt)

        // When & Then
        #expect(snapshot.isStale == false)
    }

    // MARK: - Finding Lowest Quota

    @Test
    func `snapshot finds the quota with lowest percentage`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 25, quotaType: .weekly, providerId: "claude"),
            UsageQuota(percentRemaining: 60, quotaType: .modelSpecific("opus"), providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When
        let lowest = snapshot.lowestQuota

        // Then
        #expect(lowest?.percentRemaining == 25)
        #expect(lowest?.quotaType == .weekly)
    }

    // MARK: - Provider Lookup (Rich Domain Model)

    // MARK: - Account Information

    @Test
    func `snapshot captures account information`() {
        // Given & When
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date(),
            accountEmail: "user@example.com",
            accountOrganization: "Acme Corp",
            loginMethod: "Claude Max"
        )

        // Then
        #expect(snapshot.accountEmail == "user@example.com")
        #expect(snapshot.accountOrganization == "Acme Corp")
        #expect(snapshot.loginMethod == "Claude Max")
    }

    @Test
    func `snapshot account info is optional`() {
        // Given & When
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())

        // Then
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
        #expect(snapshot.loginMethod == nil)
    }

    // MARK: - Model Specific Quotas

    @Test
    func `snapshot filters model specific quotas`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "claude"),
            UsageQuota(percentRemaining: 60, quotaType: .modelSpecific("opus"), providerId: "claude"),
            UsageQuota(percentRemaining: 50, quotaType: .modelSpecific("sonnet"), providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When
        let modelQuotas = snapshot.modelSpecificQuotas

        // Then
        #expect(modelQuotas.count == 2)
        #expect(modelQuotas.allSatisfy { quota in
            if case .modelSpecific = quota.quotaType { return true }
            return false
        })
    }

    @Test
    func `snapshot returns empty array when no model specific quotas`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // When
        let modelQuotas = snapshot.modelSpecificQuotas

        // Then
        #expect(modelQuotas.isEmpty)
    }

    // MARK: - Empty Snapshot Factory

    @Test
    func `empty snapshot factory creates snapshot with no quotas`() {
        // When
        let snapshot = UsageSnapshot.empty(for: "claude")

        // Then
        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.overallStatus == .healthy)
    }

    // MARK: - Age Description

    @Test
    func `age description shows just now for recent snapshots`() {
        // Given - snapshot from 30 seconds ago
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date().addingTimeInterval(-30)
        )

        // Then
        #expect(snapshot.ageDescription == "Just now")
    }

    @Test
    func `age description shows minutes for older snapshots`() {
        // Given - snapshot from 2 minutes ago
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date().addingTimeInterval(-120)
        )

        // Then
        #expect(snapshot.ageDescription == "2m ago")
    }

    @Test
    func `age description shows hours for old snapshots`() {
        // Given - snapshot from 2 hours ago
        let snapshot = UsageSnapshot(
            providerId: "claude",
            quotas: [],
            capturedAt: Date().addingTimeInterval(-7200)
        )

        // Then
        #expect(snapshot.ageDescription == "2h ago")
    }

    // MARK: - Session and Weekly Quota Accessors

    @Test
    func `sessionQuota returns session quota when present`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // Then
        #expect(snapshot.sessionQuota?.percentRemaining == 80)
    }

    @Test
    func `weeklyQuota returns weekly quota when present`() {
        // Given
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        // Then
        #expect(snapshot.weeklyQuota?.percentRemaining == 70)
    }

    // MARK: - Quota Groups

    @Test
    func `ungrouped snapshot has no quota groups and one unnamed bucket`() {
        let quotas = [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 70, quotaType: .weekly, providerId: "claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "claude", quotas: quotas, capturedAt: Date())

        #expect(snapshot.hasQuotaGroups == false)
        let groups = snapshot.quotaGroups
        #expect(groups.count == 1)
        #expect(groups[0].title == nil)
        #expect(groups[0].quotas.count == 2)
    }

    @Test
    func `grouped quotas bucket by group in first-appearance order`() {
        let quotas = [
            UsageQuota(percentRemaining: 90, quotaType: .timeLimit("Codex 5h"), providerId: "omp", group: "Codex"),
            UsageQuota(percentRemaining: 40, quotaType: .timeLimit("Codex 7d"), providerId: "omp", group: "Codex"),
            UsageQuota(percentRemaining: 95, quotaType: .timeLimit("Claude 5h"), providerId: "omp", group: "Claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "omp", quotas: quotas, capturedAt: Date())

        #expect(snapshot.hasQuotaGroups == true)
        let groups = snapshot.quotaGroups
        #expect(groups.map(\.title) == ["Codex", "Claude"])
        #expect(groups[0].quotas.count == 2)
        #expect(groups[0].worstStatus == .warning) // 40% remaining
        #expect(groups[0].lowestQuota?.percentRemaining == 40)
        #expect(groups[1].quotas.count == 1)
    }

    @Test
    func `grouped metrics become note-only sections after quota sections`() {
        let quotas = [
            UsageQuota(percentRemaining: 90, quotaType: .timeLimit("Claude 5h"), providerId: "omp", group: "Claude"),
        ]
        let metrics = [
            ExtensionMetric(label: "Copilot · work@example.com", value: "No usage reported", unit: "", group: "Copilot · work"),
        ]
        let snapshot = UsageSnapshot(providerId: "omp", quotas: quotas, capturedAt: Date(), extensionMetrics: metrics)

        let groups = snapshot.quotaGroups
        #expect(groups.map(\.title) == ["Claude", "Copilot · work"])
        #expect(groups[1].quotas.isEmpty)
        #expect(groups[1].note == "No usage reported")
        #expect(groups[0].note == nil)
    }

    @Test
    func `note on a quota-bearing group renders as its own row`() {
        // A metric whose group title collides with a quota group attaches
        // its note to that section - the presentation policy must surface
        // it as a row, never drop it (note-only sections keep the note in
        // the header instead, where it doubles as the summary).
        let quotas = [
            UsageQuota(percentRemaining: 90, quotaType: .timeLimit("Claude 5h"), providerId: "omp", group: "Claude"),
        ]
        let metrics = [
            ExtensionMetric(label: "Claude · solo@example.com", value: "No usage reported", unit: "", group: "Claude"),
        ]
        let snapshot = UsageSnapshot(providerId: "omp", quotas: quotas, capturedAt: Date(), extensionMetrics: metrics)

        let groups = snapshot.quotaGroups
        #expect(groups.count == 1)
        #expect(groups[0].note == "No usage reported")
        #expect(groups[0].notePlacement == .row("No usage reported"))
    }

    @Test
    func `group notes accumulate in first appearance order`() {
        let quotas = [
            UsageQuota(percentRemaining: 90, quotaType: .timeLimit("Claude 5h"), providerId: "omp", group: "Claude"),
        ]
        let metrics = [
            ExtensionMetric(label: "Claude Extra Usage", value: "Extra usage $1,234.56 spent · no cap", unit: "", group: "Claude"),
            ExtensionMetric(label: "Claude account", value: "No usage reported", unit: "", group: "Claude"),
        ]
        let snapshot = UsageSnapshot(
            providerId: "omp",
            quotas: quotas,
            capturedAt: Date(),
            extensionMetrics: metrics
        )

        #expect(snapshot.quotaGroups.first?.note == """
        Extra usage $1,234.56 spent · no cap
        No usage reported
        """)
    }

    @Test
    func `note placement is header-inline for note-only groups and nil without a note`() {
        let noteOnly = QuotaGroup(title: "Copilot", quotas: [], note: "No usage reported")
        #expect(noteOnly.notePlacement == .headerInline("No usage reported"))

        let plain = QuotaGroup(title: "Claude", quotas: [
            UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "omp", group: "Claude"),
        ])
        #expect(plain.notePlacement == nil)
    }

    @Test
    func `ungrouped metrics do not create sections`() {
        let metrics = [
            ExtensionMetric(label: "Health", value: "OK", unit: ""),
        ]
        let snapshot = UsageSnapshot(providerId: "ext", quotas: [], capturedAt: Date(), extensionMetrics: metrics)

        #expect(snapshot.hasQuotaGroups == false)
        #expect(snapshot.quotaGroups.isEmpty)
    }
}
