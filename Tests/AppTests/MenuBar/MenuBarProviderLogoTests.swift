import Testing
import AppKit
import Kit
@testable import ClaudeBar

/// *Show Provider Logo*: a single readout can start with its provider's
/// logo too. Off by default — one readout has nothing to tell apart — and
/// several providers or accounts always show theirs.
@Suite @MainActor
struct MenuBarProviderLogoTests {
    @Test func `should show no logo beside a single readout unless the person asks for it`() {
        #expect(!StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: false, hasAccountName: false, logoAlways: false))
        #expect(StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: false, hasAccountName: false, logoAlways: true))
    }

    @Test func `should always show the logo when several readouts or an account name need telling apart`() {
        #expect(StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: true, hasAccountName: false, logoAlways: false))
        #expect(StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: false, hasAccountName: true, logoAlways: false))
    }

    @Test func `should show only the status icon, no logo, when the menu bar shows no quota`() {
        #expect(!StatusItemLabelDriver.showsPrimaryLogo(showsQuota: false, hasOtherReadouts: true, hasAccountName: true, logoAlways: true))
    }

    @Test func `should show the logo alone, without a chart icon, while waiting for the first reading`() {
        #expect(!StatusItemLabelDriver.showsStatusIcon(hasLabel: false, showsLogo: true))
        #expect(StatusItemLabelDriver.showsStatusIcon(hasLabel: false, showsLogo: false))
        #expect(!StatusItemLabelDriver.showsStatusIcon(hasLabel: true, showsLogo: false))
    }

    @Test func `should show the logo alone at launch, not the logo beside a chart icon`() {
        var content = StatusItemLabelDriver.LabelContent(label: nil, fallbackStatus: .healthy, sessionPhase: nil, themeModeId: "dark")
        content.primaryProviderId = "claude"
        content.primaryProviderName = "Claude"
        let logoOnly = StatusItemLabelDriver.compose(content, theme: DarkTheme())
        content.primaryProviderId = nil
        content.primaryProviderName = nil
        let chartOnly = StatusItemLabelDriver.compose(content, theme: DarkTheme())
        // Two images joined with spacing would be wider than either alone.
        #expect(logoOnly.size.width < chartOnly.size.width + 12)
        #expect(logoOnly.size.width > 0)
    }

    @Test func `should widen the menu bar to start with the provider's logo when the logo is shown`() {
        var content = StatusItemLabelDriver.LabelContent(
            label: MenuBarLabel(text: "5h 81%", status: .healthy, segments: [.init(text: "5h 81%", status: .healthy)]),
            fallbackStatus: .healthy, sessionPhase: nil, themeModeId: "dark"
        )
        let plain = StatusItemLabelDriver.compose(content, theme: DarkTheme())
        content.primaryProviderId = "claude"
        content.primaryProviderName = "Claude"
        let withLogo = StatusItemLabelDriver.compose(content, theme: DarkTheme())
        #expect(withLogo.size.width > plain.size.width)
    }
}
