import Testing
import Foundation
@testable import ClaudeBar

/// Tests for the pure add/normalize rules behind the threshold editor UI
/// (issue #68).
@Suite
struct AlertThresholdListTests {

    @Test
    func `parses a whole number threshold`() {
        #expect(AlertThresholdList.adding("35", to: []) == [35])
    }

    @Test
    func `parses a decimal threshold`() {
        #expect(AlertThresholdList.adding("12.5", to: []) == [12.5])
    }

    @Test
    func `tolerates whitespace and a trailing percent sign`() {
        #expect(AlertThresholdList.adding(" 45% ", to: []) == [45])
    }

    @Test
    func `rejects non-numeric input`() {
        #expect(AlertThresholdList.adding("abc", to: []) == nil)
        #expect(AlertThresholdList.adding("", to: []) == nil)
    }

    @Test
    func `clamps into 0 to 100`() {
        #expect(AlertThresholdList.adding("150", to: []) == [100])
        #expect(AlertThresholdList.adding("-3", to: []) == [0])
    }

    @Test
    func `rejects duplicates of an existing threshold`() {
        #expect(AlertThresholdList.adding("35", to: [35]) == nil)
    }

    @Test
    func `appends to the existing list keeping order`() {
        #expect(AlertThresholdList.adding("10", to: [60, 35]) == [60, 35, 10])
    }

    @Test
    func `caps the list at eight thresholds`() {
        let full = [90.0, 80, 70, 60, 50, 40, 30, 20]
        #expect(AlertThresholdList.adding("10", to: full) == nil)
        #expect(AlertThresholdList.adding("10", to: Array(full.dropLast())) == Array(full.dropLast()) + [10])
    }
}
