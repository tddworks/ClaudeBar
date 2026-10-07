import Testing
import Foundation
@testable import Domain

@Suite(.serialized)
struct UsageSnapshotTests {

    // MARK: - Creating Snapshots

    @Test
    func `should hold the provider's quotas as read`() {
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
    func `should hold the session, weekly and model quotas together`() {
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
    func `should find the session quota among the provider's quotas`() {
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
    func `should find the weekly quota among the provider's quotas`() {
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
    func `should find no weekly quota when the provider reports none`() {
        // Given
        let sessionQuota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [sessionQuota], capturedAt: Date())

        // When
        let found = snapshot.quota(for: .weekly)

        // Then
        #expect(found == nil)
    }

    @Test
    func `should read back each kind of quota from its saved key and reject an unknown key`() {
        #expect(QuotaType(quotaKey: QuotaType.session.quotaKey) == .session)
        #expect(QuotaType(quotaKey: QuotaType.weekly.quotaKey) == .weekly)
        #expect(QuotaType(quotaKey: QuotaType.modelSpecific("opus").quotaKey) == .modelSpecific("opus"))
        #expect(QuotaType(quotaKey: QuotaType.timeLimit("mcp").quotaKey) == .timeLimit("mcp"))
        #expect(QuotaType(quotaKey: "model:") == nil)
        #expect(QuotaType(quotaKey: "unknown") == nil)
    }

    @Test
    func `should find a model's quota and a time-limit quota by their saved keys`() {
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
    func `should show the provider healthy when every quota is healthy`() {
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
    func `should warn for the provider when one quota is in warning`() {
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
    func `should show the provider critical when one quota is critical`() {
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
    func `should show the provider depleted when any quota is depleted`() {
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
    func `should know the usage was read two minutes ago`() {
        // Given
        let capturedAt = Date().addingTimeInterval(-120) // 2 minutes ago
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: capturedAt)

        // When
        let ageInSeconds = snapshot.age

        // Then
        #expect(ageInSeconds >= 119 && ageInSeconds <= 121)
    }

    @Test
    func `should call the usage stale when it was read over 5 minutes ago`() {
        // Given
        let capturedAt = Date().addingTimeInterval(-360) // 6 minutes ago
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: capturedAt)

        // When & Then
        #expect(snapshot.isStale == true)
    }

    @Test
    func `should call the usage fresh when it was read within 5 minutes`() {
        // Given
        let capturedAt = Date().addingTimeInterval(-60) // 1 minute ago
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: capturedAt)

        // When & Then
        #expect(snapshot.isStale == false)
    }

    // MARK: - Finding Lowest Quota

    @Test
    func `should find the quota with the least left`() {
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
    func `should show the login's email, organization and plan`() {
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
    func `should show no email, organization or plan when the provider gives none`() {
        // Given & When
        let snapshot = UsageSnapshot(providerId: "claude", quotas: [], capturedAt: Date())

        // Then
        #expect(snapshot.accountEmail == nil)
        #expect(snapshot.accountOrganization == nil)
        #expect(snapshot.loginMethod == nil)
    }

    // MARK: - Model Specific Quotas

    @Test
    func `should list only the per-model quotas among the provider's quotas`() {
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
            if case .modelSpecific = quota.quotaType.shape { return true }
            return false
        })
    }

    @Test
    func `should list no per-model quotas when the provider reports none`() {
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
    func `should show a provider with no quotas yet as healthy`() {
        // When
        let snapshot = UsageSnapshot.empty(for: "claude")

        // Then
        #expect(snapshot.providerId == "claude")
        #expect(snapshot.quotas.isEmpty)
        #expect(snapshot.overallStatus == .healthy)
    }

    // MARK: - Age Description

    @Test
    func `should say Just now when the usage was read under a minute ago`() {
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
    func `should say 2m ago when the usage was read two minutes ago`() {
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
    func `should say 2h ago when the usage was read two hours ago`() {
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
    func `should show the session quota when the provider reports one`() {
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
    func `should show the weekly quota when the provider reports one`() {
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
    func `should show every quota in one untitled section when the provider groups none`() {
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
    func `should show one section per group in the order the provider reports them, each with its worst status and lowest quota`() {
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
    func `should show a grouped note with no quotas as its own section after the quota sections`() {
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
    func `should show a note as its own row when its group also has quotas`() {
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
    func `should show every note of a group in the order the provider reports them`() {
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
    func `should show a note-only section's note in its header and place nothing when a section has no note`() {
        let noteOnly = QuotaGroup(title: "Copilot", quotas: [], note: "No usage reported")
        #expect(noteOnly.notePlacement == .headerInline("No usage reported"))

        let plain = QuotaGroup(title: "Claude", quotas: [
            UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "omp", group: "Claude"),
        ])
        #expect(plain.notePlacement == nil)
    }

    @Test
    func `should show no sections when the provider's notes belong to no group`() {
        let metrics = [
            ExtensionMetric(label: "Health", value: "OK", unit: ""),
        ]
        let snapshot = UsageSnapshot(providerId: "ext", quotas: [], capturedAt: Date(), extensionMetrics: metrics)

        #expect(snapshot.hasQuotaGroups == false)
        #expect(snapshot.quotaGroups.isEmpty)
    }

    // MARK: - Hiding quotas (issue #140)

    private func gemini(flashLeft: Double = 60) -> UsageSnapshot {
        UsageSnapshot(providerId: "gemini", quotas: [
            UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "gemini"),
            UsageQuota(percentRemaining: 25, quotaType: .weekly, providerId: "gemini"),
            UsageQuota(percentRemaining: flashLeft, quotaType: .modelSpecific("gemini-2.0-flash"), providerId: "gemini"),
        ], capturedAt: Date(), accountEmail: "me@example.com")
    }

    @Test
    func `should keep the other quotas and the login's details when the person hides a quota (#140)`() {
        let usage = gemini().hiding(["model:gemini-2.0-flash"])

        #expect(usage.quotas.map(\.quotaType) == [.session, .weekly])
        #expect(usage.accountEmail == "me@example.com")
        #expect(usage.providerId == "gemini")
    }

    @Test
    func `should change nothing when the person hides nothing or only quotas no longer reported (#140)`() {
        let usage = gemini()

        #expect(usage.hiding([]) == usage)
        #expect(usage.hiding(["time:mcp", "model:gone"]) == usage)
    }

    @Test
    func `should keep every quota when the person hides them all, so there is always something to watch (#140)`() {
        let usage = gemini()

        #expect(usage.hiding(["session", "weekly", "model:gemini-2.0-flash"]) == usage)
    }

    @Test
    func `should leave a hidden quota out of the provider's status and lowest quota (#140)`() {
        let usage = gemini(flashLeft: 10)

        #expect(usage.overallStatus == .critical)
        #expect(usage.hiding(["model:gemini-2.0-flash"]).overallStatus == .warning)
        #expect(usage.hiding(["weekly"]).lowestQuota?.quotaType == .modelSpecific("gemini-2.0-flash"))
    }

    @Test
    func `should hide a quota inside its group and keep the note-only sections (#140)`() {
        let quotas = [
            UsageQuota(percentRemaining: 90, quotaType: .timeLimit("Codex 5h"), providerId: "omp", group: "Codex"),
            UsageQuota(percentRemaining: 40, quotaType: .timeLimit("Codex 7d"), providerId: "omp", group: "Codex"),
            UsageQuota(percentRemaining: 95, quotaType: .timeLimit("Claude 5h"), providerId: "omp", group: "Claude"),
        ]
        let metrics = [ExtensionMetric(label: "Copilot", value: "No usage reported", unit: "", group: "Copilot")]
        let snapshot = UsageSnapshot(providerId: "omp", quotas: quotas, capturedAt: Date(), extensionMetrics: metrics)

        let groups = snapshot.hiding(["time:Codex 7d"]).quotaGroups

        #expect(groups.map(\.title) == ["Codex", "Claude", "Copilot"])
        #expect(groups[0].quotas.map(\.quotaType) == [.timeLimit("Codex 5h")])
        #expect(groups[2].note == "No usage reported")
    }
}
