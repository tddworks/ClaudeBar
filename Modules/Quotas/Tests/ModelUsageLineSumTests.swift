import Foundation
import Testing
@testable import Quotas

/// Two lines of one model add up to one line: every count and the cost, so a
/// range's mix never drops a field a day holds (CANONICAL §5, `ModelUsageLine`).
@Suite
struct ModelUsageLineSumTests {
    @Test func `should add every count and the cost of two lines of one model`() {
        let monday = ModelUsageLine(model: "acme-large-2", inputTokens: 100, outputTokens: 20,
                                    cacheCreationTokens: 5, cacheReadTokens: 40, totalTokens: 120, cost: 3)
        let tuesday = ModelUsageLine(model: "acme-large-2", inputTokens: 1, outputTokens: 2,
                                     cacheCreationTokens: 3, cacheReadTokens: 4, totalTokens: 3,
                                     cost: Decimal(string: "0.5")!)

        #expect(monday + tuesday == ModelUsageLine(model: "acme-large-2", inputTokens: 101, outputTokens: 22,
                                                   cacheCreationTokens: 8, cacheReadTokens: 44, totalTokens: 123,
                                                   cost: Decimal(string: "3.5")!))
    }

    @Test func `should keep the unnamed line unnamed when two of them add up`() {
        let sum = ModelUsageLine(model: "", totalTokens: 10, cost: 1) + ModelUsageLine(model: "", totalTokens: 5, cost: 2)

        #expect(sum == ModelUsageLine(model: "", totalTokens: 15, cost: 3))
    }
}
