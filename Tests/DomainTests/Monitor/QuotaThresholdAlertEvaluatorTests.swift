import Testing
import Foundation
@testable import Domain

/// Tests for the user-configured below-threshold alert evaluator (issue #68).
/// Chicago school: assert the crossings each evaluation returns.
@Suite
struct QuotaThresholdAlertEvaluatorTests {

    // MARK: - Single Threshold

    @Test
    func `returns no crossings while percent stays above threshold`() {
        var evaluator = QuotaThresholdAlertEvaluator()

        let crossed = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 40,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        #expect(crossed.isEmpty)
    }

    @Test
    func `fires when percent crosses below a user threshold`() {
        var evaluator = QuotaThresholdAlertEvaluator()

        let crossed = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 34,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        #expect(crossed == [QuotaAlertThreshold(percent: 35)])
    }

    @Test
    func `does not refire while percent stays below threshold`() {
        var evaluator = QuotaThresholdAlertEvaluator()

        _ = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 34,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )
        let again = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 30,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        #expect(again.isEmpty)
    }

    @Test
    func `refires after recovery above threshold`() {
        var evaluator = QuotaThresholdAlertEvaluator()
        _ = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 34,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        // Recovered: cleared for the next crossing.
        _ = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 50,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )
        let refired = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 34,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        #expect(refired == [QuotaAlertThreshold(percent: 35)])
    }

    @Test
    func `hovering just above threshold does not rearm`() {
        var evaluator = QuotaThresholdAlertEvaluator()
        _ = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 34,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        // Within the recovery margin of the threshold: still considered "fired".
        let rearmAttempt = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 35.5,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )
        let stillArmed = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 34.5,
            thresholds: [QuotaAlertThreshold(percent: 35)]
        )

        #expect(rearmAttempt.isEmpty)
        #expect(stillArmed.isEmpty)
    }

    // MARK: - Multiple Thresholds

    @Test
    func `multiple thresholds each fire exactly once when crossed`() {
        var evaluator = QuotaThresholdAlertEvaluator()
        let thresholds = [
            QuotaAlertThreshold(percent: 60),
            QuotaAlertThreshold(percent: 35),
            QuotaAlertThreshold(percent: 10),
        ]

        // Above all of them.
        #expect(evaluator.crossings(providerId: "claude", percentRemaining: 70, thresholds: thresholds).isEmpty)

        // Steps down through each threshold: one firing per step.
        #expect(evaluator.crossings(providerId: "claude", percentRemaining: 55, thresholds: thresholds)
            == [QuotaAlertThreshold(percent: 60)])
        #expect(evaluator.crossings(providerId: "claude", percentRemaining: 30, thresholds: thresholds)
            == [QuotaAlertThreshold(percent: 35)])
        #expect(evaluator.crossings(providerId: "claude", percentRemaining: 5, thresholds: thresholds)
            == [QuotaAlertThreshold(percent: 10)])

        // Below all of them: no refires.
        #expect(evaluator.crossings(providerId: "claude", percentRemaining: 2, thresholds: thresholds).isEmpty)
    }

    @Test
    func `crossing several thresholds at once fires each exactly once`() {
        var evaluator = QuotaThresholdAlertEvaluator()
        let thresholds = [
            QuotaAlertThreshold(percent: 60),
            QuotaAlertThreshold(percent: 35),
            QuotaAlertThreshold(percent: 10),
        ]

        let crossed = evaluator.crossings(providerId: "claude", percentRemaining: 5, thresholds: thresholds)

        #expect(crossed == [QuotaAlertThreshold(percent: 60), QuotaAlertThreshold(percent: 35),
                            QuotaAlertThreshold(percent: 10)])
    }

    // MARK: - Provider Isolation

    @Test
    func `crossing state is tracked per provider`() {
        var evaluator = QuotaThresholdAlertEvaluator()
        let thresholds = [QuotaAlertThreshold(percent: 35)]

        _ = evaluator.crossings(providerId: "claude", percentRemaining: 30, thresholds: thresholds)

        // A different provider at the same percentage has its own crossing.
        let codex = evaluator.crossings(providerId: "codex", percentRemaining: 30, thresholds: thresholds)
        #expect(codex == thresholds)
    }

    // MARK: - Edge Cases

    @Test
    func `empty threshold list never fires`() {
        var evaluator = QuotaThresholdAlertEvaluator()

        let crossed = evaluator.crossings(providerId: "claude", percentRemaining: 0, thresholds: [])

        #expect(crossed.isEmpty)
    }

    @Test
    func `a threshold of zero never fires while percent is positive`() {
        var evaluator = QuotaThresholdAlertEvaluator()

        let crossed = evaluator.crossings(
            providerId: "claude",
            percentRemaining: 0.5,
            thresholds: [QuotaAlertThreshold(percent: 0)]
        )

        #expect(crossed.isEmpty)
    }

    // MARK: - Value Type

    @Test
    func `threshold clamps percent into 0 to 100`() {
        #expect(QuotaAlertThreshold(percent: 120).percent == 100)
        #expect(QuotaAlertThreshold(percent: -5).percent == 0)
        #expect(QuotaAlertThreshold(percent: 35).percent == 35)
    }

    @Test
    func `display label drops trailing zeros`() {
        #expect(QuotaAlertThreshold(percent: 35).displayLabel == "35")
        #expect(QuotaAlertThreshold(percent: 12.5).displayLabel == "12.5")
    }
}
