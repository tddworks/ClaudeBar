import SwiftUI
import Domain

// MARK: - Provider Visual Identity Protocol

/// Defines visual identity for AI providers.
/// Each concrete provider implements this to own its visual representation.
/// This keeps visual properties with the provider (rich domain) while
/// separating SwiftUI dependencies from the Domain layer.
public protocol ProviderVisualIdentity {
    /// SF Symbol icon name for this provider
    var symbolIcon: String { get }

    /// Icon asset name in the asset catalog
    var iconAssetName: String { get }

    /// Theme color for this provider
    func themeColor(for scheme: ColorScheme) -> Color

    /// Theme gradient for this provider
    func themeGradient(for scheme: ColorScheme) -> LinearGradient
}

// MARK: - ClaudeProvider Visual Identity

extension ClaudeProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "brain.fill" }

    public var iconAssetName: String { "ClaudeIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? BaseTheme.coralAccent
            : Color(red: 0.95, green: 0.48, blue: 0.38)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark ? BaseTheme.pinkHot : Color(red: 0.92, green: 0.45, blue: 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - CodexProvider Visual Identity

extension CodexProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "chevron.left.forwardslash.chevron.right" }

    public var iconAssetName: String { "CodexIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? BaseTheme.tealBright
            : Color(red: 0.18, green: 0.72, blue: 0.68)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark
                    ? Color(red: 0.25, green: 0.65, blue: 0.85)
                    : Color(red: 0.12, green: 0.52, blue: 0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - GeminiProvider Visual Identity

extension GeminiProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "sparkles" }

    public var iconAssetName: String { "GeminiIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? BaseTheme.goldenGlow
            : Color(red: 0.92, green: 0.72, blue: 0.28)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark
                    ? Color(red: 0.95, green: 0.55, blue: 0.35)
                    : Color(red: 0.85, green: 0.45, blue: 0.25)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - CopilotProvider Visual Identity

extension CopilotProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "chevron.left.forwardslash.chevron.right" }

    public var iconAssetName: String { "CopilotIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        // GitHub's blue color
        scheme == .dark
            ? Color(red: 0.38, green: 0.55, blue: 0.93)
            : Color(red: 0.26, green: 0.43, blue: 0.82)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark
                    ? Color(red: 0.55, green: 0.40, blue: 0.90)
                    : Color(red: 0.45, green: 0.30, blue: 0.80)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - AntigravityProvider Visual Identity

extension AntigravityProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "wand.and.stars" }

    public var iconAssetName: String { "AntigravityIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        // Purple/magenta color matching Antigravity branding
        scheme == .dark
            ? Color(red: 0.72, green: 0.35, blue: 0.85)
            : Color(red: 0.58, green: 0.22, blue: 0.72)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark
                    ? Color(red: 0.45, green: 0.25, blue: 0.75)
                    : Color(red: 0.35, green: 0.15, blue: 0.65)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - ZaiProvider Visual Identity

extension ZaiProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "z.square.fill" }

    public var iconAssetName: String { "ZaiIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        // Blue color matching Z.ai branding
        scheme == .dark
            ? Color(red: 0.35, green: 0.60, blue: 1.0)
            : Color(red: 0.23, green: 0.51, blue: 0.96)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark
                    ? Color(red: 0.30, green: 0.45, blue: 0.85)
                    : Color(red: 0.20, green: 0.35, blue: 0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - BedrockProvider Visual Identity

extension BedrockProvider: ProviderVisualIdentity {
    public var symbolIcon: String { "cloud.fill" }

    public var iconAssetName: String { "BedrockIcon" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        // AWS orange color
        scheme == .dark
            ? Color(red: 1.0, green: 0.6, blue: 0.2)
            : Color(red: 0.92, green: 0.5, blue: 0.15)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                themeColor(for: scheme),
                scheme == .dark
                    ? Color(red: 0.85, green: 0.45, blue: 0.15)
                    : Color(red: 0.75, green: 0.35, blue: 0.1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - AIProvider Visual Identity Helper

/// Extension to access visual identity from any AIProvider.
/// Uses type casting to dispatch to the correct implementation.
extension AIProvider {
    /// Returns the visual identity if this provider conforms to ProviderVisualIdentity
    public var visualIdentity: ProviderVisualIdentity? {
        self as? ProviderVisualIdentity
    }

    /// SF Symbol icon, with fallback for unknown providers
    public var symbolIconOrDefault: String {
        visualIdentity?.symbolIcon ?? "questionmark.circle.fill"
    }

    /// Icon asset name, with fallback for unknown providers
    public var iconAssetNameOrDefault: String {
        visualIdentity?.iconAssetName ?? "QuestionIcon"
    }

    /// Theme color with fallback
    public func themeColorOrDefault(for scheme: ColorScheme) -> Color {
        visualIdentity?.themeColor(for: scheme) ?? BaseTheme.purpleVibrant
    }

    /// Theme gradient with fallback
    public func themeGradientOrDefault(for scheme: ColorScheme) -> LinearGradient {
        visualIdentity?.themeGradient(for: scheme) ?? LinearGradient(
            colors: [BaseTheme.coralAccent, BaseTheme.pinkHot],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Static Provider Identity Lookup

/// Static helpers to look up provider visual identity by ID string.
/// Used by views that only have a providerId, not the full AIProvider object.
enum ProviderVisualIdentityLookup {
    /// Get provider theme color by ID
    static func color(for providerId: String, scheme: ColorScheme) -> Color {
        switch providerId {
        case "claude":
            return scheme == .dark
                ? BaseTheme.coralAccent
                : Color(red: 0.95, green: 0.48, blue: 0.38)
        case "codex":
            return scheme == .dark
                ? BaseTheme.tealBright
                : Color(red: 0.18, green: 0.72, blue: 0.68)
        case "gemini":
            return scheme == .dark
                ? BaseTheme.goldenGlow
                : Color(red: 0.92, green: 0.72, blue: 0.28)
        case "copilot":
            return scheme == .dark
                ? Color(red: 0.38, green: 0.55, blue: 0.93)
                : Color(red: 0.26, green: 0.43, blue: 0.82)
        case "antigravity":
            return scheme == .dark
                ? Color(red: 0.72, green: 0.35, blue: 0.85)
                : Color(red: 0.58, green: 0.22, blue: 0.72)
        case "zai":
            return scheme == .dark
                ? Color(red: 0.35, green: 0.60, blue: 1.0)
                : Color(red: 0.23, green: 0.51, blue: 0.96)
        case "bedrock":
            return scheme == .dark
                ? Color(red: 1.0, green: 0.6, blue: 0.2)
                : Color(red: 0.92, green: 0.5, blue: 0.15)
        default:
            return BaseTheme.purpleVibrant
        }
    }

    /// Get provider gradient by ID
    static func gradient(for providerId: String, scheme: ColorScheme) -> LinearGradient {
        let primaryColor = color(for: providerId, scheme: scheme)
        let secondaryColor: Color

        switch providerId {
        case "claude":
            secondaryColor = scheme == .dark
                ? BaseTheme.pinkHot
                : Color(red: 0.92, green: 0.45, blue: 0.72)
        case "codex":
            secondaryColor = scheme == .dark
                ? Color(red: 0.25, green: 0.65, blue: 0.85)
                : Color(red: 0.12, green: 0.52, blue: 0.72)
        case "gemini":
            secondaryColor = scheme == .dark
                ? Color(red: 0.95, green: 0.55, blue: 0.35)
                : Color(red: 0.85, green: 0.45, blue: 0.25)
        case "copilot":
            secondaryColor = scheme == .dark
                ? Color(red: 0.55, green: 0.40, blue: 0.90)
                : Color(red: 0.45, green: 0.30, blue: 0.80)
        case "antigravity":
            secondaryColor = scheme == .dark
                ? Color(red: 0.45, green: 0.25, blue: 0.75)
                : Color(red: 0.35, green: 0.15, blue: 0.65)
        case "zai":
            secondaryColor = scheme == .dark
                ? Color(red: 0.30, green: 0.45, blue: 0.85)
                : Color(red: 0.20, green: 0.35, blue: 0.75)
        case "bedrock":
            secondaryColor = scheme == .dark
                ? Color(red: 0.85, green: 0.45, blue: 0.15)
                : Color(red: 0.75, green: 0.35, blue: 0.1)
        default:
            return LinearGradient(
                colors: [BaseTheme.coralAccent, BaseTheme.pinkHot],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [primaryColor, secondaryColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Get provider icon asset name by ID
    static func iconAssetName(for providerId: String) -> String {
        switch providerId {
        case "claude": return "ClaudeIcon"
        case "codex": return "CodexIcon"
        case "gemini": return "GeminiIcon"
        case "copilot": return "CopilotIcon"
        case "antigravity": return "AntigravityIcon"
        case "zai": return "ZaiIcon"
        case "bedrock": return "BedrockIcon"
        default: return "QuestionIcon"
        }
    }

    /// Get provider display name by ID
    static func name(for providerId: String) -> String {
        switch providerId {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "copilot": return "GitHub Copilot"
        case "antigravity": return "Antigravity"
        case "zai": return "Z.ai"
        case "bedrock": return "AWS Bedrock"
        default: return providerId.capitalized
        }
    }

    /// Get provider SF symbol icon by ID
    static func symbolIcon(for providerId: String) -> String {
        switch providerId {
        case "claude": return "brain.fill"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "sparkles"
        case "copilot": return "chevron.left.forwardslash.chevron.right"
        case "antigravity": return "wand.and.stars"
        case "zai": return "z.square.fill"
        case "bedrock": return "cloud.fill"
        default: return "questionmark.circle.fill"
        }
    }
}
