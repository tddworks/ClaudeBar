import Foundation
import Testing
@testable import Quotas

/// A model's name on a tight row, by a mechanical rule: a trailing size tag
/// and date go, and a leading segment goes when at least two remain — no
/// vendor named. The unnamed line reads as a dash.
@Suite
struct ModelUsageLineNameTests {
    @Test func `should read a model's name without its leading segment and date`() {
        #expect(ModelUsageLine(model: "claude-opus-4-6-20251101").displayName == "opus-4-6")
        #expect(ModelUsageLine(model: "claude-sonnet-5").displayName == "sonnet-5")
        #expect(ModelUsageLine(model: "acme-glm-4.6").displayName == "glm-4.6")
    }

    @Test func `should read a model's name without its size tag`() {
        #expect(ModelUsageLine(model: "qwen3-coder:30b").displayName == "qwen3-coder")
    }

    @Test func `should read a name with nothing to strip as it is`() {
        #expect(ModelUsageLine(model: "glm-4.6").displayName == "glm-4.6")
        #expect(ModelUsageLine(model: "minimax-m2").displayName == "minimax-m2")
    }

    @Test func `should read the unnamed line as a dash`() {
        #expect(ModelUsageLine(model: "").displayName == "—")
    }
}
