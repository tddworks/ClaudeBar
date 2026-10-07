import SwiftUI
import Kit

/// A text field for configuring a custom web card URL per provider.
/// Shows below the provider toggle when enabled.
struct CustomCardURLField: View {
    let providerId: String

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var urlText: String = ""
    @State private var isEditing: Bool = false

    var body: some View {

        let _ = KitObservation.track()
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary)

                Text("CUSTOM CARD")
                    .font(theme.font(size: 8, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .tracking(0.5)

                Spacer()

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        Kit.shared.setCustomCardURL(url: nil, providerId: providerId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("https://example.com", text: $urlText)
                .textFieldStyle(.plain)
                .font(theme.font(size: 10, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.glassBackground.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                        )
                )
                .onSubmit {
                    saveURL()
                }
                .onChange(of: urlText) { _, _ in
                    saveURL()
                }
        }
        .onAppear {
            urlText = Kit.shared.customCardURL(providerId: providerId) ?? ""
        }
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Kit.shared.setCustomCardURL(url: nil, providerId: providerId)
        } else {
            Kit.shared.setCustomCardURL(url: trimmed, providerId: providerId)
        }
    }
}
