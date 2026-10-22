import Testing
@testable import Domain

/// The popover's usage sections, each the person's to show or hide
/// (docs/settings.md, `app.usageSections`).
@Suite
struct UsageSectionTests {
    @Test
    func `should show today, the thirty days and the weekly recap until the person hides them`() {
        #expect(UsageSection.today.isShownByDefault)
        #expect(UsageSection.lastThirtyDays.isShownByDefault)
        #expect(UsageSection.weeklyRecap.isShownByDefault)
    }

    @Test
    func `should keep the year's sections hidden until the person shows them`() {
        #expect(!UsageSection.lastYear.isShownByDefault)
        #expect(!UsageSection.modelMix.isShownByDefault)
        #expect(!UsageSection.projectMix.isShownByDefault)
    }

    @Test
    func `should read the year only for the year's heatmap, the model mix and the projects`() {
        #expect(UsageSection.allCases.filter(\.readsTheYear) == [.lastYear, .modelMix, .projectMix])
    }

    @Test
    func `should offer the six sections in the order the popover shows them`() {
        #expect(UsageSection.allCases == [.today, .lastThirtyDays, .lastYear, .modelMix, .projectMix, .weeklyRecap])
    }
}
