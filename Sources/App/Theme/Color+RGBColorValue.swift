import AppKit
import SwiftUI
import Domain

extension Color {
    init(_ rgb: RGBColorValue) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// Nil when the color can't be resolved to sRGB (pattern or unresolved dynamic colors).
    var rgbColorValue: RGBColorValue? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGBColorValue(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent)
        )
    }
}
