import Testing
@testable import Domain

@Suite
struct MenuBarStackedSizeTests {

    // MARK: - Raw Value Persistence

    @Test
    func `small size has small raw value`() {
        #expect(MenuBarStackedSize.small.rawValue == "small")
    }

    @Test
    func `medium size has medium raw value`() {
        #expect(MenuBarStackedSize.medium.rawValue == "medium")
    }

    @Test
    func `large size has large raw value`() {
        #expect(MenuBarStackedSize.large.rawValue == "large")
    }

    @Test
    func `can be created from raw value`() {
        #expect(MenuBarStackedSize(rawValue: "small") == .small)
        #expect(MenuBarStackedSize(rawValue: "medium") == .medium)
        #expect(MenuBarStackedSize(rawValue: "large") == .large)
        #expect(MenuBarStackedSize(rawValue: "invalid") == nil)
    }

    // MARK: - Fallback Decoding

    @Test
    func `default is small`() {
        #expect(MenuBarStackedSize.default == .small)
    }

    @Test
    func `known stored values decode to their case`() {
        #expect(MenuBarStackedSize(storedRawValue: "small") == .small)
        #expect(MenuBarStackedSize(storedRawValue: "medium") == .medium)
        #expect(MenuBarStackedSize(storedRawValue: "large") == .large)
    }

    @Test
    func `unknown stored value falls back to small`() {
        // A settings file written by a newer build (or edited by hand) must
        // never break this build: unrecognized sizes quietly render small.
        #expect(MenuBarStackedSize(storedRawValue: "extra-large") == .small)
        #expect(MenuBarStackedSize(storedRawValue: "") == .small)
    }

    // MARK: - Display Label

    @Test
    func `display labels read Small Medium Large`() {
        #expect(MenuBarStackedSize.small.displayLabel == "Small")
        #expect(MenuBarStackedSize.medium.displayLabel == "Medium")
        #expect(MenuBarStackedSize.large.displayLabel == "Large")
    }
}
