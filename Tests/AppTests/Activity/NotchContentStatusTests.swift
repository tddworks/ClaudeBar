import Testing
import Foundation
import Domain
@testable import ClaudeBar

/// The notch paints a quota by the person's status policy, the same one the
/// menu bar and the cards read. Painting it by the absolute bands put a red
/// 19% beside *Room to spare* under pace-aware (#707).
@Suite
struct NotchContentStatusTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(left: Double, elapsed: Double) -> UsageQuota {
        let length: TimeInterval = 5 * 3600
        return UsageQuota(
            percentRemaining: left, quotaType: .session, providerId: "claude",
            resetsAt: now.addingTimeInterval(length * (100 - elapsed) / 100),
            windowDuration: length
        )
    }

    @Test
    func `should paint a low quota that lasts until the reset healthy under pace-aware`() {
        let content = NotchContent(policy: .paceAware)

        #expect(content.status(of: session(left: 19, elapsed: 97.3), at: now) == .healthy)
    }

    @Test
    func `should paint a quota that runs out soon critical under pace-aware`() {
        let content = NotchContent(policy: .paceAware)

        // 60% left, 3.5% of 5 hours gone: empty in about 16 minutes.
        #expect(content.status(of: session(left: 60, elapsed: 3.5), at: now) == .critical)
    }

    @Test
    func `should paint by the absolute bands under absolute`() {
        let content = NotchContent(policy: .absolute)

        #expect(content.status(of: session(left: 19, elapsed: 97.3), at: now) == .critical)
        #expect(content.status(of: session(left: 60, elapsed: 3.5), at: now) == .healthy)
    }
}
