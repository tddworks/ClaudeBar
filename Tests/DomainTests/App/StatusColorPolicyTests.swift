import Foundation
import Testing
@testable import Domain

@Suite
struct StatusColorPolicyTests {

    // MARK: - RGBColorValue

    @Test
    func `should read back the hex color the person typed`() {
        let color = RGBColorValue(hex: "#1A7A3C")
        #expect(color != nil)
        #expect(color?.hexString == "#1A7A3C")
    }

    @Test
    func `should accept a lowercase hex color without a hash and refuse a malformed one`() {
        #expect(RGBColorValue(hex: "ff5c5c")?.hexString == "#FF5C5C")
        #expect(RGBColorValue(hex: "#zz0000") == nil)
        #expect(RGBColorValue(hex: "#123") == nil)
    }

    @Test
    func `should measure white on black at 21 to 1 either way round`() {
        let white = RGBColorValue(red: 1, green: 1, blue: 1)
        let black = RGBColorValue(red: 0, green: 0, blue: 0)
        let ratio = RGBColorValue.contrastRatio(white, black)
        #expect(abs(ratio - 21) < 0.01)
        #expect(RGBColorValue.contrastRatio(black, white) == ratio)
    }

    @Test
    func `should save a color as its hex string and read it back`() throws {
        let data = try JSONEncoder().encode(RGBColorValue(hex: "#B81F1F")!)
        #expect(String(data: data, encoding: .utf8) == "\"#B81F1F\"")
        let decoded = try JSONDecoder().decode(RGBColorValue.self, from: data)
        #expect(decoded.hexString == "#B81F1F")
    }

    // MARK: - High Contrast Palettes

    @Test
    func `should show every status at 4.5 to 1 contrast or better on a light menu bar in high contrast`() {
        for status in [QuotaStatus.healthy, .warning, .critical, .depleted] {
            let color = StatusPalette.highContrastLight[status]
            let ratio = RGBColorValue.contrastRatio(color, MenuBarSurface.light)
            #expect(ratio >= 4.5, "\(status) measured \(ratio):1 on light")
        }
    }

    @Test
    func `should show every status at 4.5 to 1 contrast or better on a dark menu bar in high contrast`() {
        for status in [QuotaStatus.healthy, .warning, .critical, .depleted] {
            let color = StatusPalette.highContrastDark[status]
            let ratio = RGBColorValue.contrastRatio(color, MenuBarSurface.dark)
            #expect(ratio >= 4.5, "\(status) measured \(ratio):1 on dark")
        }
    }

    // MARK: - Overrides

    @Test
    func `should start with no custom status colors`() {
        let overrides = StatusColorOverrides.none
        #expect(overrides.isEmpty)
        #expect(overrides[.healthy] == nil)
        #expect(overrides[.depleted] == nil)
    }

    @Test
    func `should read back one custom status color after saving and leave the others unset`() throws {
        var overrides = StatusColorOverrides.none
        overrides[.critical] = RGBColorValue(hex: "#112233")

        let data = try JSONEncoder().encode(overrides)
        let decoded = try JSONDecoder().decode(StatusColorOverrides.self, from: data)

        #expect(decoded == overrides)
        #expect(decoded[.critical]?.hexString == "#112233")
        #expect(decoded[.healthy] == nil)
        #expect(decoded[.warning] == nil)
        #expect(decoded[.depleted] == nil)
        #expect(!decoded.isEmpty)
    }

    // MARK: - Policy Precedence

    @Test
    func `should leave every status color to the theme by default`() {
        let policy = StatusColorPolicy.default
        #expect(!policy.isActive)
        for status in [QuotaStatus.healthy, .warning, .critical, .depleted] {
            #expect(policy.color(for: status, appearance: .light) == nil)
            #expect(policy.color(for: status, appearance: .dark) == nil)
        }
    }

    @Test
    func `should use the high-contrast palette for the light or dark menu bar when the person turns it on`() {
        let policy = StatusColorPolicy(overrides: .none, highContrastEnabled: true)
        #expect(policy.isActive)
        #expect(policy.color(for: .warning, appearance: .light) == StatusPalette.highContrastLight[.warning])
        #expect(policy.color(for: .warning, appearance: .dark) == StatusPalette.highContrastDark[.warning])
    }

    @Test
    func `should use the person's own color for that status only, over high contrast`() {
        var overrides = StatusColorOverrides.none
        let custom = RGBColorValue(hex: "#ABCDEF")!
        overrides[.critical] = custom
        let policy = StatusColorPolicy(overrides: overrides, highContrastEnabled: true)

        #expect(policy.color(for: .critical, appearance: .light) == custom)
        #expect(policy.color(for: .critical, appearance: .dark) == custom)
        #expect(policy.color(for: .healthy, appearance: .light) == StatusPalette.highContrastLight[.healthy])
    }

    @Test
    func `should use the person's own color for one status and leave the rest to the theme`() {
        var overrides = StatusColorOverrides.none
        overrides[.healthy] = RGBColorValue(hex: "#000000")
        let policy = StatusColorPolicy(overrides: overrides, highContrastEnabled: false)

        #expect(policy.isActive)
        #expect(policy.color(for: .healthy, appearance: .dark)?.hexString == "#000000")
        #expect(policy.color(for: .warning, appearance: .dark) == nil)
    }
}
