import SwiftUI
import Domain

/// A text field for configuring a custom web card URL per provider.
/// Shows below the provider toggle when enabled.
struct CustomCardURLField: View {
    let providerId: String

    @ObservedObject var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var urlText: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)

                Text("CUSTOM CARD")
                    .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)

                Spacer()

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        settings.provider.setCustomCardURL(nil, forProvider: providerId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("https://example.com", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundColor(theme.textPrimary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.glassBackground.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.glassBorder, lineWidth: 1)
                        )
                )
                .onSubmit {
                    saveURL()
                }
                .onChange(of: urlText) { _ in
                    saveURL()
                }
        }
        .onAppear {
            urlText = settings.provider.customCardURL(forProvider: providerId) ?? ""
        }
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settings.provider.setCustomCardURL(nil, forProvider: providerId)
        } else {
            settings.provider.setCustomCardURL(trimmed, forProvider: providerId)
        }
    }
}
