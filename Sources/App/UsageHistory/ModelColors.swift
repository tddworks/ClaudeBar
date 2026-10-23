import SwiftUI
import Domain

/// The colours a model keeps between the views of one range: its place among
/// the range's models, so the same model reads the same hue in the chart and
/// in the mix. Hues far apart, cycled when a log names more models than the
/// palette holds; the unnamed line is grey.
enum ModelColors {
    static let palette: [Color] = [.purple, .green, .blue, .orange, .pink, .cyan, .indigo, .mint, .red]

    /// The colour of the model at `index` among a range's models.
    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }

    /// The colour a range gives `model` — its place among the range's models;
    /// grey for the unnamed line, or a model the range doesn't name.
    static func color(of model: String, in days: Days) -> Color {
        guard let index = days.models.firstIndex(of: model) else { return .gray }
        return color(at: index)
    }

    /// The colour a split gives `project` — the same palette, by the
    /// project's place among the split's names; grey for the unnamed part.
    static func color(ofProject project: String, in split: ByProject) -> Color {
        guard let index = split.names.firstIndex(of: project) else { return .gray }
        return color(at: index)
    }
}