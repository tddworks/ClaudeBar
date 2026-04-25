import SwiftUI
import Domain

/// A simple overlay that shows the referral link with copy functionality.
struct SharePassOverlay: View {
    let pass: ClaudePass
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Card
            VStack(spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.accentPrimary)

                    Text("Share Claude Code")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Referral Link
                HStack(spacing: 8) {
                    Text(pass.referralURL.absoluteString)
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        copyToClipboard()
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 14))
                            .foregroundColor(copied ? theme.statusHealthy : theme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                )

                // Action buttons
                HStack(spacing: 10) {
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(copied ? "Copied!" : "Copy Link")
                                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(theme.accentGradient)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(pass.referralURL)
                        onDismiss()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "safari")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Open")
                                .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        }
                        .foregroundColor(theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(theme.glassBackground)
                                .overlay(
                                    Capsule()
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Help text
                Text("Share a free week of Claude Code with friends")
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.glassBackground)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(theme.glassBorder, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 20, y: 10)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pass.referralURL.absoluteString, forType: .string)

        withAnimation(.spring()) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                copied = false
            }
        }
    }
}

// MARK: - Preview

struct SharePassOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            DarkTheme().backgroundGradient

            SharePassOverlay(
                pass: ClaudePass(
                    referralURL: URL(string: "https://claude.ai/referral/DJ_kWX90Xw")!
                ),
                onDismiss: {}
            )
        }
        .frame(width: 380, height: 400)
    }
}
