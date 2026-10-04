import Testing
import AppKit
import Domain
@testable import ClaudeBar

/// *Show Provider Logo*: a single readout can start with its provider's
/// logo too. Off by default — one readout has nothing to tell apart — and
/// several providers or accounts always show theirs.
@Suite @MainActor
struct MenuBarProviderLogoTests {
    @Test func `a single readout has no logo unless asked`() {
        #expect(!StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: false, hasAccountName: false, logoAlways: false))
        #expect(StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: false, hasAccountName: false, logoAlways: true))
    }

    @Test func `readouts to tell apart always have logos`() {
        #expect(StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: true, hasAccountName: false, logoAlways: false))
        #expect(StatusItemLabelDriver.showsPrimaryLogo(showsQuota: true, hasOtherReadouts: false, hasAccountName: true, logoAlways: false))
    }

    @Test func `without a readout there is no logo, only the status icon`() {
        #expect(!StatusItemLabelDriver.showsPrimaryLogo(showsQuota: false, hasOtherReadouts: true, hasAccountName: true, logoAlways: true))
    }

    @Test func `with the logo the label starts with it`() {
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
