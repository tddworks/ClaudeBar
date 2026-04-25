import SwiftUI

// MARK: - Provider Icon View

/// A view that displays the appropriate icon for each AI provider
/// Icons fill the entire circle like OpenRouter's design
struct ProviderIconView: View {
    let providerId: String
    var size: CGFloat = 24
    var showGlow: Bool = true

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if showGlow {
                // Subtle glow behind icon - adapts to theme
                Circle()
                    .fill(ProviderVisualIdentityLookup.color(for: providerId, scheme: colorScheme).opacity(colorScheme == .dark ? 0.3 : 0.2))
                    .frame(width: size * 1.3, height: size * 1.3)
                    .blur(radius: size * 0.3)
            }

            // Provider icon - fills the entire circle with adaptive border
            if let nsImage = loadProviderIcon(for: providerId) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.6)
                                    : theme.accentPrimary.opacity(0.3),
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: colorScheme == .dark
                            ? .black.opacity(0.15)
                            : theme.accentPrimary.opacity(0.15),
                        radius: 3,
                        y: 1
                    )
            } else {
                // Fallback: Use system symbol with gradient background
                ZStack {
                    Circle()
                        .fill(ProviderVisualIdentityLookup.gradient(for: providerId, scheme: colorScheme))
                        .frame(width: size, height: size)

                    Image(systemName: providerSymbol(for: providerId))
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundColor(.white)
                }
                .overlay(
                    Circle()
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.6)
                                : ProviderVisualIdentityLookup.color(for: providerId, scheme: colorScheme).opacity(0.3),
                            lineWidth: 2
                        )
                )
                .shadow(
                    color: colorScheme == .dark
                        ? .black.opacity(0.15)
                        : ProviderVisualIdentityLookup.color(for: providerId, scheme: colorScheme).opacity(0.15),
                    radius: 3,
                    y: 1
                )
            }
        }
    }

    private func loadProviderIcon(for providerId: String) -> NSImage? {
        let assetName = ProviderVisualIdentityLookup.iconAssetName(for: providerId)

        // Load from asset catalog
        if let image = NSImage(named: assetName) {
            return image
        }

        return nil
    }

    private func providerSymbol(for providerId: String) -> String {
        switch providerId {
        case "claude": return "brain.head.profile"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "sparkles"
        case "zai": return "z.square.fill"
        case "copilot": return "chevron.left.forwardslash.chevron.right"
        case "minimax": return "waveform"
        default: return "questionmark"
        }
    }
}

// MARK: - Preview

struct ProviderIconsDark_Previews: PreviewProvider {
    static var previews: some View {
    HStack(spacing: 30) {
        VStack {
            ProviderIconView(providerId: "claude", size: 40)
            Text("Claude")
                .font(.caption)
                .foregroundColor(.white)
        }
        VStack {
            ProviderIconView(providerId: "codex", size: 40)
            Text("Codex")
                .font(.caption)
                .foregroundColor(.white)
        }
        VStack {
            ProviderIconView(providerId: "gemini", size: 40)
            Text("Gemini")
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    .padding(40)
    .background(DarkTheme().backgroundGradient)
    .preferredColorScheme(.dark)
    }
}

struct ProviderIconsLight_Previews: PreviewProvider {
    static var previews: some View {
    HStack(spacing: 30) {
        VStack {
            ProviderIconView(providerId: "claude", size: 40)
            Text("Claude")
                .font(.caption)
                .foregroundColor(LightTheme().textPrimary)
        }
        VStack {
            ProviderIconView(providerId: "codex", size: 40)
            Text("Codex")
                .font(.caption)
                .foregroundColor(LightTheme().textPrimary)
        }
        VStack {
            ProviderIconView(providerId: "gemini", size: 40)
            Text("Gemini")
                .font(.caption)
                .foregroundColor(LightTheme().textPrimary)
        }
    }
    .padding(40)
    .background(LightTheme().backgroundGradient)
    .preferredColorScheme(.light)
    }
}

struct ProviderIconsSizes_Previews: PreviewProvider {
    static var previews: some View {
    HStack(spacing: 20) {
        ProviderIconView(providerId: "claude", size: 24)
        ProviderIconView(providerId: "claude", size: 32)
        ProviderIconView(providerId: "claude", size: 40)
        ProviderIconView(providerId: "claude", size: 48)
    }
    .padding(40)
    .background(DarkTheme().backgroundGradient)
    .preferredColorScheme(.dark)
    }
}
