import Testing
@testable import Domain

@Suite
struct MenuBarStackedSizeTests {

    // MARK: - Raw Value Persistence

    @Test
    func `should save the small stacked size as small`() {
        #expect(MenuBarStackedSize.small.rawValue == "small")
    }

    @Test
    func `should save the medium stacked size as medium`() {
        #expect(MenuBarStackedSize.medium.rawValue == "medium")
    }

    @Test
    func `should save the large stacked size as large`() {
        #expect(MenuBarStackedSize.large.rawValue == "large")
    }

    @Test
    func `should read back each saved stacked size and refuse an unknown one`() {
        #expect(MenuBarStackedSize(rawValue: "small") == .small)
        #expect(MenuBarStackedSize(rawValue: "medium") == .medium)
        #expect(MenuBarStackedSize(rawValue: "large") == .large)
        #expect(MenuBarStackedSize(rawValue: "invalid") == nil)
    }

    // MARK: - Fallback Decoding

    @Test
    func `should stack the menu bar small by default`() {
        #expect(MenuBarStackedSize.default == .small)
    }

    @Test
    func `should read each known saved stacked size as itself`() {
        #expect(MenuBarStackedSize(storedRawValue: "small") == .small)
        #expect(MenuBarStackedSize(storedRawValue: "medium") == .medium)
        #expect(MenuBarStackedSize(storedRawValue: "large") == .large)
    }

    @Test
    func `should stack small when the saved size is unknown or empty`() {
        // A settings file written by a newer build (or edited by hand) must
        // never break this build: unrecognized sizes quietly render small.
        #expect(MenuBarStackedSize(storedRawValue: "extra-large") == .small)
        #expect(MenuBarStackedSize(storedRawValue: "") == .small)
    }

    // MARK: - Display Label

    @Test
    func `should label the sizes Small, Medium and Large`() {
        #expect(MenuBarStackedSize.small.displayLabel == "Small")
        #expect(MenuBarStackedSize.medium.displayLabel == "Medium")
        #expect(MenuBarStackedSize.large.displayLabel == "Large")
    }
}
