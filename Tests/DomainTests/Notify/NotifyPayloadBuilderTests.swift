import Testing
import Foundation
@testable import Domain

@Suite
struct NotifyPayloadBuilderTests {
    private let builder = NotifyPayloadBuilder()

    /// The status colors as the gateway receives them, named here so an
    /// expectation reads as a color rather than as six hex digits.
    private let healthyTint = "#59EBAD"
    private let warningTint = "#FAB859"
    private let criticalTint = "#FA6B85"

    private func reading(
        _ percentRemaining: Double,
        provider: String = "claude",
        name: String = "Claude",
        quotaType: QuotaType = .session,
        resetsAt: Date? = nil,
        dollarRemaining: Decimal? = nil,
        compactTitle: String? = nil
    ) -> NotifyQuotaReading {
        NotifyQuotaReading(
            providerId: provider,
            providerName: name,
            quota: UsageQuota(
                percentRemaining: percentRemaining,
                quotaType: quotaType,
                providerId: provider,
                resetsAt: resetsAt,
                dollarRemaining: dollarRemaining,
                compactTitle: compactTitle
            )
        )
    }

    // MARK: - Nothing to say

    @Test
    func `no readings produce the empty payload`() {
        let payload = builder.payload(readings: [])

        #expect(payload == .empty)
        #expect(payload.isEmpty)
        #expect(payload.tile == nil)
        #expect(payload.gauge == nil)
    }

    // MARK: - The worst quota leads

    @Test
    func `the worst status leads the tile`() {
        // Given one window of each severity, from three different providers
        let readings = [
            reading(80, provider: "claude", name: "Claude", quotaType: .weekly),
            reading(35, provider: "codex", name: "Codex"),
            reading(8, provider: "gemini", name: "Gemini"),
        ]

        // When
        let payload = builder.payload(readings: readings)

        // Then the critical window sets the color and takes the first cell
        #expect(payload.tile?.tintHex == criticalTint)
        #expect(payload.tile?.metrics.first?.label == "Gemini 5h")
    }

    // MARK: - Ordering

    @Test
    func `readings tied on status are ordered by how little is left`() {
        let payload = builder.payload(readings: [
            reading(40, quotaType: .session),
            reading(30, quotaType: .weekly),
        ])

        #expect(payload.tile?.metrics.map(\.value) == ["30", "40"])
        #expect(payload.tile?.tintHex == warningTint)
    }

    @Test
    func `readings tied on how little is left are ordered by provider name`() {
        let payload = builder.payload(readings: [
            reading(30, provider: "zai", name: "Z.ai"),
            reading(30, provider: "claude", name: "Claude"),
        ])

        #expect(payload.tile?.metrics.map(\.label) == ["Claude 5h", "Z.ai 5h"])
    }

    @Test
    func `readings tied on provider name are ordered by quota key`() {
        let payload = builder.payload(readings: [
            reading(30, quotaType: .weekly),
            reading(30, quotaType: .session),
        ])

        #expect(payload.tile?.metrics.map(\.label) == ["5h", "7d"])
    }

    @Test
    func `the same readings in a different order build the same payload`() {
        // The driver drops a payload identical to the last one, so an unstable
        // order would mean republishing forever.
        let readings = [
            reading(30, quotaType: .session),
            reading(30, quotaType: .weekly),
            reading(30, provider: "codex", name: "Codex"),
            reading(8, provider: "gemini", name: "Gemini"),
            reading(72, provider: "zai", name: "Z.ai", quotaType: .weekly),
        ]

        let first = builder.payload(readings: readings.shuffled())
        let second = builder.payload(readings: readings.shuffled())

        #expect(first == second)
        #expect(first.tile?.metrics.map(\.label) == [
            "Gemini 5h", "Claude 5h", "Claude 7d", "Codex 5h", "Z.ai 7d",
        ])
    }

    @Test
    func `only the first six windows reach the metrics row`() {
        // Six is the gateway's ceiling, and more than six is unreadable on a
        // Lock Screen anyway.
        let readings = [
            reading(4, quotaType: .session),
            reading(12, quotaType: .weekly),
            reading(23, quotaType: .modelSpecific("opus")),
            reading(31, provider: "codex", name: "Codex", quotaType: .session),
            reading(38, provider: "codex", name: "Codex", quotaType: .weekly),
            reading(46, provider: "codex", name: "Codex", quotaType: .modelSpecific("gpt-5")),
            reading(57, provider: "gemini", name: "Gemini", quotaType: .session),
            reading(68, provider: "gemini", name: "Gemini", quotaType: .weekly),
            reading(79, provider: "gemini", name: "Gemini", quotaType: .modelSpecific("pro")),
        ]

        let payload = builder.payload(readings: readings)

        #expect(payload.tile?.metrics.count == 6)
        #expect(payload.tile?.metrics.first?.value == "4")
        #expect(payload.tile?.metrics.last?.value == "46")
    }

    // MARK: - Labels

    @Test
    func `labels omit the provider name when every window is one provider's`() {
        let payload = builder.payload(readings: [
            reading(70, quotaType: .session),
            reading(80, quotaType: .weekly),
        ])

        #expect(payload.tile?.metrics.map(\.label) == ["5h", "7d"])
    }

    @Test
    func `labels name the provider when more than one is reporting`() {
        let payload = builder.payload(readings: [
            reading(70, provider: "claude", name: "Claude"),
            reading(80, provider: "codex", name: "Codex"),
        ])

        #expect(payload.tile?.metrics.map(\.label) == ["Claude 5h", "Codex 5h"])
    }

    @Test
    func `a quota's compact title wins over the window's short label`() {
        // A probe that already named the window better than "7d" knows more
        // about it than the quota type does.
        let payload = builder.payload(readings: [
            reading(70, quotaType: .weekly, compactTitle: "Spark 7d"),
        ])

        #expect(payload.tile?.metrics.first?.label == "Spark 7d")
    }

    // MARK: - The bar

    @Test
    func `the tile bar follows the worst percentage based quota`() {
        let payload = builder.payload(readings: [
            reading(70, quotaType: .weekly),
            reading(45, quotaType: .session),
        ])

        #expect(payload.tile?.progress == 45)
    }

    @Test
    func `a money headline keeps the bar rather than dropping it`() {
        // Given a nearly spent credit balance as the worst reading
        let readings = [
            reading(
                5,
                provider: "ampcode",
                name: "Amp Code",
                quotaType: .modelSpecific("credits"),
                dollarRemaining: Decimal(string: "2.10")
            ),
            reading(70, provider: "claude", name: "Claude", quotaType: .weekly),
        ]

        // When
        let payload = builder.payload(readings: readings)

        // Then the balance leads, and the bar falls through to the window that
        // actually has a percentage to draw
        #expect(payload.tile?.tintHex == criticalTint)
        #expect(payload.tile?.metrics.first?.value == "$2.10")
        #expect(payload.tile?.progress == 70)
    }

    // MARK: - Numbers

    @Test
    func `a percentage renders what is remaining, not what is used`() {
        let payload = builder.payload(readings: [reading(42)])

        #expect(payload.tile?.metrics.first?.value == "42")
        #expect(payload.tile?.metrics.first?.unit == "%")
        #expect(payload.gauge?.value == "42")
    }

    @Test
    func `a money based quota renders its balance with no percent unit`() {
        let payload = builder.payload(readings: [
            reading(
                60,
                provider: "ampcode",
                name: "Amp Code",
                quotaType: .modelSpecific("credits"),
                dollarRemaining: Decimal(string: "2.10")
            ),
        ])

        #expect(payload.tile?.metrics.first?.value == "$2.10")
        #expect(payload.tile?.metrics.first?.unit == nil)
        #expect(payload.gauge?.value == "$2.10")
        #expect(payload.gauge?.unit == nil)
        #expect(payload.gauge?.progress == nil)
    }

    // MARK: - The gauge

    @Test
    func `the gauge shows the window the user selected`() {
        // Given a worse window than the one the user pinned
        let readings = [
            reading(8, provider: "claude", name: "Claude"),
            reading(70, provider: "codex", name: "Codex", quotaType: .weekly),
        ]

        // When
        let payload = builder.payload(
            readings: readings,
            gaugeSelection: NotifyGaugeSelection(providerId: "codex", quotaKey: "weekly")
        )

        // Then the pinned window is what the widget draws
        #expect(payload.gauge?.value == "70")
        #expect(payload.gauge?.progress == 70)
        #expect(payload.gauge?.tintHex == healthyTint)
        #expect(payload.gauge?.detail?.contains("Codex 7d") == true)
    }

    @Test
    func `the gauge falls back to the headline when the selection is automatic`() {
        let payload = builder.payload(readings: [
            reading(8, provider: "claude", name: "Claude"),
            reading(70, provider: "codex", name: "Codex", quotaType: .weekly),
        ])

        #expect(payload.gauge?.value == "8")
        #expect(payload.gauge?.tintHex == criticalTint)
        #expect(payload.gauge?.detail?.contains("Claude 5h") == true)
    }

    @Test
    func `the gauge falls back to the headline when the selected window stops reporting`() {
        // A provider the user switched off, or a probe that stopped returning
        // that window, must not leave the widget blank.
        let payload = builder.payload(
            readings: [
                reading(8, provider: "claude", name: "Claude"),
                reading(70, provider: "codex", name: "Codex", quotaType: .weekly),
            ],
            gaugeSelection: NotifyGaugeSelection(providerId: "gemini", quotaKey: "session")
        )

        #expect(payload.gauge?.value == "8")
        #expect(payload.gauge?.detail?.contains("Claude 5h") == true)
    }

    // MARK: - Surfaces the user turned off

    @Test
    func `turning the tile off yields a payload with no tile`() {
        let payload = builder.payload(readings: [reading(42)], includesTile: false)

        #expect(payload.tile == nil)
        #expect(payload.gauge?.value == "42")
    }

    @Test
    func `turning the gauge off yields a payload with no gauge`() {
        let payload = builder.payload(readings: [reading(42)], includesGauge: false)

        #expect(payload.gauge == nil)
        #expect(payload.tile?.metrics.first?.value == "42")
    }

    @Test
    func `turning the Home Screen tile off yields a payload with no screen tile`() {
        let payload = builder.payload(readings: [reading(42)], includesScreenTile: false)

        #expect(payload.screenTile == nil)
        #expect(payload.tile?.metrics.first?.value == "42")
    }

    @Test
    func `the Home Screen tile survives the Live Activity being turned off`() {
        // The two surfaces switch on and off separately, which is the whole
        // reason the payload carries them as two fields. A user who wants a tile
        // that stays and nothing on their Lock Screen must still get one.
        let payload = builder.payload(readings: [reading(42)], includesTile: false)

        #expect(payload.tile == nil)
        #expect(payload.screenTile?.metrics.first?.value == "42")
    }

    @Test
    func `the Home Screen tile is the Live Activity tile, one value on two surfaces`() {
        // The gateway derives both routes' content contracts from one module and
        // takes the same body on either, so the client sends one body to both.
        // Building the two separately here could only produce two pictures of
        // one quota that were meant to be identical and one day were not.
        let payload = builder.payload(readings: [
            reading(8, provider: "claude", name: "Claude"),
            reading(70, provider: "codex", name: "Codex", quotaType: .weekly),
        ])

        #expect(payload.screenTile != nil)
        #expect(payload.screenTile == payload.tile)
    }

    // MARK: - The summary line

    @Test
    func `the summary names the provider, the window, the percentage and the countdown`() {
        // Given a window that resets in a bit over two hours. The countdown
        // ticks while the test runs, so only its shape is asserted.
        let payload = builder.payload(readings: [
            reading(42, resetsAt: Date().addingTimeInterval(2 * 3600 + 30)),
        ])

        // Then
        #expect(payload.tile?.body?.contains("Claude 5h") == true)
        #expect(payload.tile?.body?.contains("42% left") == true)
        #expect(payload.tile?.body?.contains("resets in") == true)
        #expect(payload.tile?.trailing != nil)
    }

    @Test
    func `two readings that tie on everything visible still order deterministically`() {
        // An aggregating provider can report two accounts under one display
        // name, so the name is not a unique key and neither is the pair of name
        // and window. Swift's sort is not stable, so without a total comparator
        // these two could come back in either order, the payload would differ
        // between builds of identical state, and the driver would republish for
        // nothing on every refresh.
        let left = NotifyQuotaReading(
            providerId: "omp-work",
            providerName: "Oh My Pi",
            quota: UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "omp-work")
        )
        let right = NotifyQuotaReading(
            providerId: "omp-home",
            providerName: "Oh My Pi",
            quota: UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "omp-home")
        )

        let oneWay = NotifyPayloadBuilder.ordered([left, right]).map(\.providerId)
        let theOther = NotifyPayloadBuilder.ordered([right, left]).map(\.providerId)

        #expect(oneWay == theOther)
        #expect(oneWay == ["omp-home", "omp-work"])
    }

}
