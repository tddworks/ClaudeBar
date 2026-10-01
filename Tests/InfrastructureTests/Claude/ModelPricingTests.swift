import Foundation
import Testing
@testable import Infrastructure

@Suite
struct ModelPricingTests {
    /// A record with 1M in / 100K out / 1M cache-write / 1M cache-read tokens.
    private func record(model: String) -> TokenUsageRecord {
        TokenUsageRecord(
            messageId: nil,
            requestId: nil,
            model: model,
            inputTokens: 1_000_000,
            outputTokens: 100_000,
            cacheCreationTokens: 1_000_000,
            cacheReadTokens: 1_000_000,
            timestamp: Date()
        )
    }

    @Test func `sonnet pricing matches published rates`() {
        let price = ModelPricing.price(for: "claude-sonnet-4-6")
        #expect(price.inputPer1M == 3)
        #expect(price.outputPer1M == 15)
        #expect(price.cacheWritePer1M == Decimal(string: "3.75"))
        #expect(price.cacheReadPer1M == Decimal(string: "0.30"))
    }

    @Test func `opus 4_6 pricing matches published rates`() {
        let price = ModelPricing.price(for: "claude-opus-4-6")
        #expect(price.inputPer1M == 5)
        #expect(price.outputPer1M == 25)
        #expect(price.cacheWritePer1M == Decimal(string: "6.25"))
        #expect(price.cacheReadPer1M == Decimal(string: "0.50"))
    }

    @Test func `unknown model falls back to sonnet pricing`() {
        let price = ModelPricing.price(for: "some-unknown-model")
        #expect(price.inputPer1M == 3)
        #expect(price.outputPer1M == 15)
    }

    @Test func `model with opus in name uses opus 4_6 pricing`() {
        let price = ModelPricing.price(for: "claude-opus-4-99-20260101")
        #expect(price.inputPer1M == 5)
    }

    @Test func `calculates cost for token usage record`() {
        let record = TokenUsageRecord(
            messageId: nil,
            requestId: nil,
            model: "claude-sonnet-4-6",
            inputTokens: 1_000_000, // $3
            outputTokens: 100_000,  // $1.50
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            timestamp: Date()
        )
        let cost = ModelPricing.cost(for: record)
        #expect(cost == Decimal(string: "4.5"))
    }

    @Test func `calculates cost including cache tokens`() {
        let record = TokenUsageRecord(
            messageId: nil,
            requestId: nil,
            model: "claude-sonnet-4-6",
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 1_000_000, // $3.75
            cacheReadTokens: 1_000_000,     // $0.30
            timestamp: Date()
        )
        let cost = ModelPricing.cost(for: record)
        #expect(cost == Decimal(string: "4.05"))
    }

    @Test func `calculates cache savings as input price minus cache read price`() {
        // Sonnet: input $3/M, cache_read $0.30/M → save $2.70 per 1M cache reads
        let record = TokenUsageRecord(
            messageId: nil,
            requestId: nil,
            model: "claude-sonnet-4-6",
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 1_000_000,
            timestamp: Date()
        )
        let savings = ModelPricing.savings(for: record)
        #expect(savings == Decimal(string: "2.7"))
    }

    @Test func `cache savings is zero when no cache reads`() {
        let record = TokenUsageRecord(
            messageId: nil,
            requestId: nil,
            model: "claude-sonnet-4-6",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            timestamp: Date()
        )
        #expect(ModelPricing.savings(for: record) == 0)
    }

    @Test func `cache savings scales with cache read tokens`() {
        // Opus 4.6: input $5/M, cache_read $0.50/M → save $4.50 per 1M
        let record = TokenUsageRecord(
            messageId: nil,
            requestId: nil,
            model: "claude-opus-4-6",
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 2_000_000,
            timestamp: Date()
        )
        // 2M × $4.50/M = $9.00
        #expect(ModelPricing.savings(for: record) == 9)
    }

    // MARK: - Locally served models (issue #190)

    @Test func `local model produces zero cost`() {
        #expect(ModelPricing.cost(for: record(model: "qwen3-coder")) == 0)
    }

    @Test func `local model with runtime tag produces zero cost`() {
        // ollama / LM Studio echo the tag back: "qwen3-coder:30b", "qwen2.5-coder:7b".
        #expect(ModelPricing.cost(for: record(model: "qwen3-coder:30b")) == 0)
    }

    @Test func `local model produces zero cache savings`() {
        // Cache savings at Anthropic rates would be a fabricated number for a model
        // nobody bills per token.
        #expect(ModelPricing.savings(for: record(model: "llama-3.3-70b-instruct")) == 0)
    }

    @Test func `unpriced model costs nothing when the session is served locally`() {
        // Provenance beats the name list: a local server may serve a model whose name
        // we have never seen, and no per-token price can exist for it.
        #expect(ModelPricing.cost(for: record(model: "some-unknown-model"), servedLocally: true) == 0)
    }

    @Test func `known anthropic model still costs list price`() {
        // Regression guard: real spend keeps being counted.
        #expect(ModelPricing.cost(for: record(model: "claude-sonnet-4-6")) == Decimal(string: "8.55"))
    }

    @Test func `known anthropic model keeps list price when served locally`() {
        // The price table stays authoritative for names it knows: a loopback endpoint
        // says nothing about which Anthropic model was billed, and scanning two days
        // would otherwise retroactively zero real spend from before the switch.
        #expect(ModelPricing.cost(for: record(model: "claude-sonnet-4-6"), servedLocally: true)
            == Decimal(string: "8.55"))
    }

    @Test func `known anthropic model keeps cache savings when served locally`() {
        #expect(ModelPricing.savings(for: record(model: "claude-sonnet-4-6"), servedLocally: true)
            == Decimal(string: "2.7"))
    }

    @Test func `paid gateway model keeps the sonnet estimate`() {
        // A remote gateway may bill per token, so an unpriced name there is still
        // estimated — the local fix must not zero out Zai / DeepSeek / proxy users.
        #expect(ModelPricing.price(for: "glm-4.6").inputPer1M == 3)
        #expect(ModelPricing.price(for: "deepseek-r1").inputPer1M == 3)
    }
}
