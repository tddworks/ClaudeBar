import Testing
import Foundation
import AppKit
import Domain
import Infrastructure
@testable import ClaudeBar

@Suite @MainActor
struct TouchBarQuotaSyncTests {
    @Test
    func `touchbar and menubar percentages match exactly for fractional values without rounding up`() {
        // Test cases from user: 6.8% used -> menubar 6%, touchbar must also be 6% (not 7%)
        // 56.7% used -> menubar 56%, touchbar must also be 56% (not 57%)
        let testValues: [(percentRemaining: Double, expectedUsedInt: Int, expectedRemainingInt: Int)] = [
            (93.2, 6, 93),   // 100 - 93.2 = 6.8 -> 6%
            (43.3, 56, 43),  // 100 - 43.3 = 56.7 -> 56%
            (0.1, 99, 0),    // 100 - 0.1 = 99.9 -> 99%
            (99.5, 0, 99),   // 100 - 99.5 = 0.5 -> 0%
            (50.0, 50, 50),
        ]

        for test in testValues {
            let quota = UsageQuota(
                percentRemaining: test.percentRemaining,
                quotaType: .session,
                providerId: "claude"
            )

            // Menu Bar .used mode
            let menuBarUsed = MenuBarPercentageDisplay(quota: quota, mode: .used)
            #expect(menuBarUsed.text == "\(test.expectedUsedInt)%")

            // Menu Bar .remaining mode
            let menuBarRemaining = MenuBarPercentageDisplay(quota: quota, mode: .remaining)
            #expect(menuBarRemaining.text == "\(test.expectedRemainingInt)%")

            // Touch Bar gauge in .used mode
            let usedGauge = TouchBarProviderGauge(
                providerId: "claude",
                name: "Claude",
                percentUsed: quota.displayPercent(mode: .used),
                resetText: "2h",
                status: .healthy,
                hasQuota: true
            )
            #expect(Int(usedGauge.percentUsed) == test.expectedUsedInt)
            #expect("\(Int(usedGauge.percentUsed))%" == menuBarUsed.text)

            // Touch Bar gauge in .remaining mode
            let remainingGauge = TouchBarProviderGauge(
                providerId: "claude",
                name: "Claude",
                percentUsed: quota.displayPercent(mode: .remaining),
                resetText: "2h",
                status: .healthy,
                hasQuota: true
            )
            #expect(Int(remainingGauge.percentUsed) == test.expectedRemainingInt)
            #expect("\(Int(remainingGauge.percentUsed))%" == menuBarRemaining.text)
        }
    }

    @Test
    func `touchbar quota view draws matching text`() {
        let quota = UsageQuota(
            percentRemaining: 93.2, // percentUsed = 6.8
            quotaType: .session,
            providerId: "claude"
        )
        let menuBarDisplay = MenuBarPercentageDisplay(quota: quota, mode: .used)
        #expect(menuBarDisplay.text == "6%")

        let gauge = TouchBarProviderGauge(
            providerId: "claude",
            name: "Claude",
            percentUsed: quota.displayPercent(mode: .used),
            resetText: "2h",
            status: .healthy,
            hasQuota: true
        )

        let view = TouchBarQuotaView(frame: NSRect(x: 0, y: 0, width: 600, height: 30))
        view.gauges = [gauge]

        // Force a draw pass to ensure no crashes and valid layout
        let image = NSImage(size: NSSize(width: 600, height: 30), flipped: false) { rect in
            view.draw(rect)
            return true
        }
        #expect(image.isValid)
    }
}
