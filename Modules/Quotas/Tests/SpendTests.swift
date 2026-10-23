import Foundation
import Testing
@testable import Quotas

/// What a part of a day spent: tokens by kind and their cost. It adds up
/// field by field and reads itself in a unit, for a model's line and a
/// project's alike (CANONICAL §5, `Spend`).
@Suite
struct SpendTests {
    private let spend = Spend(inputTokens: 100, outputTokens: 20, cacheCreationTokens: 10,
                              cacheReadTokens: 40, totalTokens: 120, cost: 12)

    @Test func `should add every count and the cost`() {
        let more = Spend(inputTokens: 1, outputTokens: 2, cacheCreationTokens: 3, cacheReadTokens: 4,
                         totalTokens: 3, cost: 0.5)

        #expect(spend + more == Spend(inputTokens: 101, outputTokens: 22, cacheCreationTokens: 13,
                                      cacheReadTokens: 44, totalTokens: 123, cost: 12.5))
    }

    @Test func `should leave what remains of a whole once a part is taken`() {
        let part = Spend(inputTokens: 60, cacheReadTokens: 40, totalTokens: 70, cost: 2)

        #expect(spend - part == Spend(inputTokens: 40, outputTokens: 20, cacheCreationTokens: 10,
                                      totalTokens: 50, cost: 10))
        #expect(spend - spend == .none)
    }

    @Test func `should read itself in the unit asked`() {
        #expect(spend.value(in: .cost) == 12)
        #expect(spend.value(in: .tokens) == 120)
        #expect(spend.value(in: .cache) == 50)
    }
}
