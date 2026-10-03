import SwiftUI
import Domain

/// A simple overlay that shows the referral link with copy functionality.
struct SharePassOverlay: View {
    let pass: GuestPass
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
                        .popoverFont(16, weight: .semibold)
                        .foregroundStyle(theme.accentPrimary)

                    Text("Share Claude Code")
                        .popoverFont(14, weight: .bold)
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .popoverFont(18)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Referral Link
                HStack(spacing: 8) {
                    Text(pass.referralURL.absoluteString)
                        .popoverFont(11, weight: .medium)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        copyToClipboard()
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .popoverFont(14)
                            .foregroundStyle(copied ? theme.statusHealthy : theme.accentPrimary)
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
                                .popoverFont(11, weight: .semibold)
                            Text(copied ? "Copied!" : "Copy Link")
                                .popoverFont(11, weight: .medium)
                        }
                        .foregroundStyle(.white)
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
                                .popoverFont(11, weight: .semibold)
                            Text("Open")
                                .popoverFont(11, weight: .medium)
                        }
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(theme.glassBackground)
                                .overlay(
                                    Capsule()
                                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Help text
                Text("Share a free week of Claude Code with friends")
                    .popoverFont(10, weight: .semibold)
                    .foregroundStyle(theme.textTertiary)
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
                            .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.3)) {
                copied = false
            }
        }
    }
}

// MARK: - Error Overlay

/// Shown when fetching the invitation link fails, so a tapped Share button
/// never does nothing at all (issue #243).
struct SharePassErrorOverlay: View {
    let message: String
    let onDismiss: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .popoverFont(16, weight: .semibold)
                        .foregroundStyle(theme.statusCritical)

                    Text("Couldn't Get Invitation Link")
                        .popoverFont(14, weight: .bold)
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .popoverFont(18)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Text(message)
                    .popoverFont(11, weight: .medium)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Invitation links are only available on Claude Max plans.")
                    .popoverFont(10, weight: .semibold)
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 20, y: 10)
            )
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}

// MARK: - Preview

#Preview("SharePassOverlay") {
    ZStack {
        DarkTheme().backgroundGradient

        SharePassOverlay(
            pass: GuestPass(
                referralURL: URL(string: "https://claude.ai/referral/DJ_kWX90Xw")!
            ),
            onDismiss: {}
        )
    }
    .frame(width: 380, height: 400)
}
