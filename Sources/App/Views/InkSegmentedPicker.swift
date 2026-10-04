import SwiftUI

/// A segmented picker in an outlined theme's ink: one outlined capsule, the
/// chosen option filled with ink, which slides to the option you pick.
/// macOS can't restyle SwiftUI's segmented `Picker`, so this draws its own
/// look and hands VoiceOver a real `Picker` for the same choice.
struct InkSegmentedPicker<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    @Environment(\.appTheme) private var theme
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.cardGradient))
        .overlay(Capsule().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth * 0.8))
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ option: Option) -> some View {
        let isOn = selection == option
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option }
        } label: {
            Text(label(option))
                .font(.system(size: 9.5, weight: .heavy, design: theme.fontDesign))
                .foregroundStyle(isOn ? theme.cardGradient : LinearGradient(colors: [theme.textPrimary], startPoint: .leading, endPoint: .trailing))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background {
                    if isOn {
                        Capsule()
                            .fill(theme.glassBorder)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
