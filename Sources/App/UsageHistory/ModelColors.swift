import AppKit
import SwiftUI
import Domain

/// The colours a model keeps between the views of one range: its place among
/// the range's models in name order, so the same model reads the same hue in
/// the chart, the mix and the recap's report. Hues far apart, cycled when a
/// log names more models than the palette holds; the unnamed line is grey.
/// The palette is the App's one list of hues — a recap's providers take theirs
/// from it too, and the report its hex.
enum ModelColors {
    static let palette: [Color] = [.purple, .green, .blue, .orange, .pink, .cyan, .indigo, .mint, .red]
    /// The unnamed line's colour, and a model the range doesn't name.
    static let unnamed: Color = .gray

    /// The colour at `index` in the palette, cycled.
    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }

    /// The colour a range gives `model` — its place among the range's models;
    /// grey for the unnamed line, or a model the range doesn't name.
    static func color(of model: String, in days: Days) -> Color {
        index(of: model, among: days.models).map(color(at:)) ?? unnamed
    }

    /// `model`'s place among `models` — the models a range names, in name
    /// order, the unnamed line not among them (`Days.models`). Nil for the
    /// unnamed line, or a model not among them.
    static func index(of model: String, among models: [String]) -> Int? {
        Set(models).filter { !$0.isEmpty }.sorted().firstIndex(of: model)
    }

    /// `color` as `#RRGGBB` in the light or dark appearance — the palette
    /// written out for a page that has no SwiftUI.
    static func hex(_ color: Color, dark: Bool) -> String {
        var hex = "#8E8E93"
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        appearance?.performAsCurrentDrawingAppearance {
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            hex = String(format: "#%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent),
                         channel(rgb.blueComponent))
        }
        return hex
    }

    private static func channel(_ value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }

    /// The colour a split gives `project` — the same palette, by the
    /// project's place among the split's names; grey for the unnamed part.
    static func color(ofProject project: String, in split: ByProject) -> Color {
        guard let index = split.names.firstIndex(of: project) else { return .gray }
        return color(at: index)
    }
}
