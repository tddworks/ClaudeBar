import Testing
import Foundation
@testable import Monitoring

/// *Refresh faster while a quota moves* (#642): after each background tick
/// the wait halves when a quota rose, and doubles back to the chosen
/// interval when nothing did.
@Suite
struct AdaptiveCadenceTests {
    private let resetsAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ used: Double, resetsAt: Date? = nil) -> [String: AdaptiveCadence.Reading] {
        ["claude/session": AdaptiveCadence.Reading(percentUsed: used, resetsAt: resetsAt ?? self.resetsAt)]
    }

    @Test
    func `should wait the chosen interval after the first tick, with nothing to compare`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))

        #expect(cadence.next(after: reading(10)) == .seconds(600))
    }

    @Test
    func `should halve the wait while a quota moves, never below a minute`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(10))

        let waits = [12.0, 14, 16, 18, 20].map { cadence.next(after: reading($0)) }

        #expect(waits == [.seconds(300), .seconds(150), .seconds(75), .seconds(60), .seconds(60)])
    }

    @Test
    func `should double the wait while nothing moves, never above the chosen interval`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(10))
        _ = cadence.next(after: reading(20))
        _ = cadence.next(after: reading(30))

        let waits = (0..<3).map { _ in cadence.next(after: reading(30)) }

        #expect(waits == [.seconds(300), .seconds(600), .seconds(600)])
    }

    @Test
    func `should not count a rise under one point as movement`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(10))

        #expect(cadence.next(after: reading(10.5)) == .seconds(600))
        #expect(cadence.next(after: reading(11.5)) == .seconds(300))
    }

    @Test
    func `should not count a new window as movement`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(2))

        let nextWindow = resetsAt.addingTimeInterval(5 * 3600)

        #expect(cadence.next(after: reading(40, resetsAt: nextWindow)) == .seconds(600))
    }

    @Test
    func `should count a rise as movement when the reset time drifts by a minute`() {
        // A reset read as "in 3h 20m" lands a little differently every probe.
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(10))

        #expect(cadence.next(after: reading(15, resetsAt: resetsAt.addingTimeInterval(55))) == .seconds(300))
    }

    @Test
    func `should count a reset time 15 minutes off as the same window, and 16 as a new one`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(10))

        #expect(cadence.next(after: reading(15, resetsAt: resetsAt.addingTimeInterval(15 * 60))) == .seconds(300))
        #expect(cadence.next(after: reading(20, resetsAt: resetsAt.addingTimeInterval(31 * 60))) == .seconds(600))
    }

    @Test
    func `should count a rise in any one quota as movement`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        let first: [String: AdaptiveCadence.Reading] = [
            "claude/session": .init(percentUsed: 10, resetsAt: resetsAt),
            "codex/weekly": .init(percentUsed: 40, resetsAt: nil),
        ]
        _ = cadence.next(after: first)

        var second = first
        second["codex/weekly"] = .init(percentUsed: 42, resetsAt: nil)

        #expect(cadence.next(after: second) == .seconds(300))
    }

    @Test
    func `should not count a quota that appears or a fall as movement`() {
        var cadence = AdaptiveCadence(ceiling: .seconds(600))
        _ = cadence.next(after: reading(30))

        var later = reading(20)
        later["codex/weekly"] = .init(percentUsed: 90, resetsAt: nil)

        #expect(cadence.next(after: later) == .seconds(600))
    }
}
