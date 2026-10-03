import Testing
@testable import Domain

@Suite
struct PopoverTextSizeTests {

    // MARK: - Raw Value Persistence

    @Test
    func `each size has its own raw value`() {
        #expect(PopoverTextSize.small.rawValue == "small")
        #expect(PopoverTextSize.medium.rawValue == "medium")
        #expect(PopoverTextSize.large.rawValue == "large")
        #expect(PopoverTextSize.extraLarge.rawValue == "extraLarge")
        #expect(PopoverTextSize(rawValue: "invalid") == nil)
    }

    // MARK: - Fallback Decoding

    @Test
    func `default is medium`() {
        #expect(PopoverTextSize.default == .medium)
    }

    @Test
    func `known stored values decode to their case`() {
        #expect(PopoverTextSize(storedRawValue: "small") == .small)
        #expect(PopoverTextSize(storedRawValue: "medium") == .medium)
        #expect(PopoverTextSize(storedRawValue: "large") == .large)
        #expect(PopoverTextSize(storedRawValue: "extraLarge") == .extraLarge)
    }

    @Test
    func `unknown stored value falls back to default`() {
        // A settings file written by a newer build (or edited by hand) must
        // never break this build: an unrecognized size quietly renders default.
        #expect(PopoverTextSize(storedRawValue: "jumbo") == .medium)
        #expect(PopoverTextSize(storedRawValue: "") == .medium)
    }

    // MARK: - Display Label

    @Test
    func `display labels read Small Default Large Extra Large`() {
        #expect(PopoverTextSize.small.displayLabel == "Small")
        #expect(PopoverTextSize.medium.displayLabel == "Default")
        #expect(PopoverTextSize.large.displayLabel == "Large")
        #expect(PopoverTextSize.extraLarge.displayLabel == "Extra Large")
    }

    // MARK: - The Picker Is Complete

    @Test
    func `all cases are the four offered sizes, smallest first`() {
        // The settings control renders `allCases`, so a case missing here is a
        // size the user can never pick.
        #expect(PopoverTextSize.allCases == [.small, .medium, .large, .extraLarge])
    }
}