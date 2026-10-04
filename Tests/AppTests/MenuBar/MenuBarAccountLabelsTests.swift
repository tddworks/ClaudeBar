import Testing
import AppKit
import Domain
@testable import ClaudeBar

/// *Show Account Labels in Menu Bar* off: the short account names beside the
/// icons go, and the icons and quotas stay exactly where they were (#365).
@Suite @MainActor
struct MenuBarAccountLabelsTests {
    @Test(arguments: [false, true])
    func `without its name a primary account keeps its icon and quota`(stacked: Bool) throws {
        let theme = DarkTheme()
        var content = content(stacked: stacked)
        content.accountNames = ["codex": "personal"]
        let named = StatusItemLabelDriver.compose(content, theme: theme)
        content.accountNames = [:]
        let unnamed = StatusItemLabelDriver.compose(content, theme: theme)

        #expect(unnamed.size.width < named.size.width)
        #expect(unnamed.size.height == named.size.height)
    }

    @Test(arguments: [false, true])
    func `without names every pinned account keeps its icon and quota`(stacked: Bool) throws {
        let theme = DarkTheme()
        var content = content(stacked: stacked)
        content.additionalLabels = [MenuBarProviderLabel(
            providerId: "codex.work", providerName: "work@example.com", label: content.label!, stacked: stacked
        )]
        content.accountNames = ["codex": "personal", "codex.work": "work"]
        let named = StatusItemLabelDriver.compose(content, theme: theme)
        content.accountNames = ["codex": "personal"]
        let primaryOnly = StatusItemLabelDriver.compose(content, theme: theme)
        content.accountNames = [:]
        let unnamed = StatusItemLabelDriver.compose(content, theme: theme)

        #expect(primaryOnly.size.width < named.size.width)
        #expect(unnamed.size.width < primaryOnly.size.width)
        #expect(unnamed.size.height == named.size.height)
    }

    private func content(stacked: Bool) -> StatusItemLabelDriver.LabelContent {
        StatusItemLabelDriver.LabelContent(
            label: MenuBarLabel(text: "5h 40% | 7d 60%", status: .healthy, segments: [
                .init(text: "5h 40%", status: .healthy),
                .init(text: "7d 60%", status: .healthy),
            ]),
            primaryProviderId: "codex", primaryProviderName: "Personal",
            fallbackStatus: .healthy, sessionPhase: nil, themeModeId: "dark", stacked: stacked
        )
    }
}
