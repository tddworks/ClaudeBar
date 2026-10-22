import Foundation
import Testing
@testable import Quotas

/// Which models a person leans on over a range: each model summed over the
/// range, largest first in the unit asked, the unnamed line among them so the
/// parts add up to the range, each with its share (CANONICAL §5, `ModelMix`).
@Suite
struct ModelMixTests {
    private let monday = Date(timeIntervalSince1970: 1_760_000_000)
    private let tuesday = Date(timeIntervalSince1970: 1_760_086_400)

    private let large = ModelUsageLine(model: "acme-large-2", inputTokens: 100, totalTokens: 120, cost: 12)
    private let small = ModelUsageLine(model: "acme-small-1", inputTokens: 300, totalTokens: 400, cost: 2)
    private let unnamed = ModelUsageLine(model: "", totalTokens: 50, cost: 1)

    private func day(_ date: Date, _ lines: [ModelUsageLine]) -> DailyUsageStat {
        DailyUsageStat(date: date, totalCost: lines.reduce(0) { $0 + $1.cost },
                       totalTokens: lines.reduce(0) { $0 + $1.totalTokens }, workingTime: 0, sessionCount: 1,
                       lines: lines)
    }

    @Test func `should sum each model over the range, largest first`() {
        let days = Days([day(monday, [large, small]), day(tuesday, [small])], knowsCost: true)

        let mix = ModelMix(of: days, in: .cost)

        #expect(mix.parts.map(\.line.model) == ["acme-large-2", "acme-small-1"])
        #expect(mix.parts.map(\.value) == [12, 4])
        #expect(mix.parts.last?.line.totalTokens == 800)
    }

    @Test func `should rank the models in the unit asked`() {
        let days = Days([day(monday, [large, small])], knowsCost: true)

        #expect(ModelMix(of: days, in: .tokens).parts.map(\.line.model) == ["acme-small-1", "acme-large-2"])
    }

    @Test func `should keep the unnamed line in the mix, so the parts add up to the range`() {
        let days = Days([day(monday, [large, unnamed])], knowsCost: true)

        let mix = ModelMix(of: days, in: .cost)

        #expect(mix.parts.map(\.line.model) == ["acme-large-2", ""])
        #expect(mix.parts.reduce(0) { $0 + $1.value } == days.total(in: .cost))
    }

    @Test func `should give each model its share of the range`() {
        let big = ModelUsageLine(model: "acme-large-2", cost: 3)
        let little = ModelUsageLine(model: "acme-small-1", cost: 1)

        let mix = ModelMix(of: Days([day(monday, [big, little])], knowsCost: true), in: .cost)

        #expect(mix.parts.map(\.share) == [0.75, 0.25])
    }

    @Test func `should order models that tie by name`() {
        let zed = ModelUsageLine(model: "zed-1", cost: 2)
        let alpha = ModelUsageLine(model: "alpha-1", cost: 2)

        let mix = ModelMix(of: Days([day(monday, [zed, alpha])], knowsCost: true), in: .cost)

        #expect(mix.parts.map(\.line.model) == ["alpha-1", "zed-1"])
    }

    @Test func `should name the model leaned on most as the top one`() {
        let days = Days([day(monday, [small, large])], knowsCost: true)

        #expect(ModelMix(of: days, in: .cost).top?.line.model == "acme-large-2")
    }

    @Test func `should have no top model and no share when nothing was used`() {
        let idle = ModelUsageLine(model: "acme-large-2")

        let mix = ModelMix(of: Days([day(monday, [idle])], knowsCost: true), in: .cost)

        #expect(mix.parts.map(\.share) == [0])
        #expect(ModelMix(of: Days([], knowsCost: true), in: .cost).top == nil)
    }

    /// The unnamed line is a part of the mix, never a model, so it is never
    /// the top one.
    @Test func `should name the largest model as the top one when unnamed records spent more`() {
        let days = Days([day(monday, [small, ModelUsageLine(model: "", totalTokens: 900, cost: 90)])], knowsCost: true)

        #expect(ModelMix(of: days, in: .cost).top?.line.model == small.model)
    }

    @Test func `should have no top model when no record names one`() {
        let days = Days([day(monday, [unnamed])], knowsCost: true)

        #expect(ModelMix(of: days, in: .cost).top == nil)
    }
}
