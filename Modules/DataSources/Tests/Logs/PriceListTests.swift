import Foundation
import Testing
@testable import DataSources

/// A price file is data: a model is priced by the first rule that knows it,
/// and money stays exact.
@Suite
struct PriceListTests {
    static let file = """
    {
      "per": 1000000,
      "models": [
        { "id": "m-large-2", "input": "5", "output": "25", "cacheWrite": "6.25", "cacheWrite1h": "10", "cacheRead": "0.50" },
        { "id": "m-medium-2", "input": "3", "output": "15", "cacheWrite": "3.75", "cacheRead": "0.30" },
        { "id": "m-small-1", "input": "1", "output": "5", "cacheWrite": "1.25", "cacheRead": "0.10" }
      ],
      "families": [ { "contains": "large", "as": "m-large-2" }, { "contains": "small", "as": "m-small-1" } ],
      "free": [ "llama", "qwen" ],
      "otherwise": { "input": "3", "output": "15", "cacheWrite": "3.75", "cacheRead": "0.30" }
    }
    """

    private let prices = PriceList.load("prices.json", from: { _ in PriceListTests.file })!

    /// 1M in, 100K out, 1M cache write, 1M cache read.
    private func record(_ model: String) -> LogRecord {
        LogRecord(at: Date(), model: model, input: 1_000_000, output: 100_000, cacheWrite: 1_000_000, cacheRead: 1_000_000)
    }

    @Test func `an exact id has its own price`() {
        let price = prices.price(for: "m-medium-2")
        #expect([price.input, price.output, price.cacheWrite, price.cacheRead] == [3, 15, Decimal(string: "3.75")!, Decimal(string: "0.30")!])
    }

    @Test func `a dated id takes the price of the id it starts with`() {
        #expect(prices.price(for: "m-medium-2-20260101").input == 3)
    }

    @Test func `a family in the name prices a model the list doesn't have`() {
        #expect(prices.price(for: "m-large-99-20260101").input == 5)
    }

    @Test func `an unknown model gets the fallback, never zero by omission`() {
        #expect(prices.price(for: "acme-unknown").input == 3)
    }

    @Test func `a free family costs nothing, its runtime tag too`() {
        #expect(prices.cost(of: record("qwen3-coder:30b")) == 0)
        #expect(prices.savings(of: record("llama-3.3-70b")) == 0)
    }

    @Test func `an unpriced model on a local route costs nothing`() {
        #expect(prices.cost(of: record("acme-internal-7b"), servedLocally: true) == 0)
    }

    @Test func `a listed model keeps its price on a local route`() {
        #expect(prices.cost(of: record("m-medium-2"), servedLocally: true) == Decimal(string: "8.55"))
        #expect(prices.savings(of: record("m-medium-2"), servedLocally: true) == Decimal(string: "2.7"))
    }

    @Test func `cost is every kind of token at its price, exact`() {
        let plain = LogRecord(at: Date(), model: "m-medium-2", input: 1_000_000, output: 100_000)
        let cached = LogRecord(at: Date(), model: "m-medium-2", cacheWrite: 1_000_000, cacheRead: 1_000_000)
        #expect(prices.cost(of: plain) == Decimal(string: "4.5"))
        #expect(prices.cost(of: cached) == Decimal(string: "4.05"))
    }

    @Test func `savings are cache reads at the input price less what they cost`() {
        let reads = LogRecord(at: Date(), model: "m-large-2", cacheRead: 2_000_000)
        #expect(prices.savings(of: reads) == 9)
        #expect(prices.savings(of: LogRecord(at: Date(), model: "m-large-2", input: 1_000_000)) == 0)
    }

    @Test func `a write kept an hour has its own price; the rest the five-minute one`() {
        let writes = LogRecord(at: Date(), model: "m-large-2", cacheWrite: 1_000_000, cacheWrite1h: 600_000)
        // 0.4M × $6.25 + 0.6M × $10.
        #expect(prices.cost(of: writes) == Decimal(string: "8.5"))
    }

    @Test func `without an hour price, every write costs the five-minute price`() {
        let writes = LogRecord(at: Date(), model: "m-medium-2", cacheWrite: 1_000_000, cacheWrite1h: 600_000)
        #expect(prices.cost(of: writes) == Decimal(string: "3.75"))
    }

    @Test func `a missing or malformed file is no price list`() {
        #expect(PriceList.load("prices.json", from: { _ in nil }) == nil)
        #expect(PriceList.load("prices.json", from: { _ in "{" }) == nil)
    }
}
