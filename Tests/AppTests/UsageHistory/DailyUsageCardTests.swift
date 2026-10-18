import Testing
import Foundation
import SwiftUI
import Domain
@testable import ClaudeBar

/// The daily usage cards sit two to a row, so a big day's number has half the
/// popover to fit in. It shrinks to fit; it never wraps onto a second line.
@Suite
struct DailyUsageCardTests {

    @Test @MainActor
    func `should keep a big day's cost and tokens on one line at every text size`() throws {
        // The bug: a big day's "$2,345.67" or "4567.8M" broke over two and
        // three lines, so its card grew taller than a small day's. Shrunk to
        // fit, its line can come out a point shorter, never taller.
        let small = report(cost: 1, tokens: 500)
        let big = report(cost: Decimal(string: "2345.67")!, tokens: 4_567_800_000)

        for textSize in PopoverTextSize.allCases {
            for metric in [DailyUsageMetric.cost, .tokens] {
                let smallCard = try #require(renderedHeight(of: card(metric, small, at: textSize)))
                let bigCard = try #require(renderedHeight(of: card(metric, big, at: textSize)))
                #expect(bigCard <= smallCard, "\(metric) at \(textSize)")
            }
        }
    }

    private func report(cost: Decimal, tokens: Int) -> DailyUsageReport {
        let today = Date()
        return DailyUsageReport(
            today: DailyUsageStat(date: today, totalCost: cost, totalTokens: tokens,
                                  workingTime: 3600, sessionCount: 1),
            previous: .empty(for: today.addingTimeInterval(-86_400))
        )
    }

    /// A card as wide as one of the two in a row of the popover at that size.
    @MainActor
    private func card(_ metric: DailyUsageMetric, _ report: DailyUsageReport,
                      at textSize: PopoverTextSize) -> some View {
        DailyUsageCardView(metric: metric, report: report, delay: 0)
            .frame(width: (textSize.popoverWidth - 2 * 16 - 10) / 2)
            .environment(\.popoverTextSize, textSize)
    }

    @MainActor
    private func renderedHeight<V: View>(of view: V) -> Int? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage?.height
    }
}
