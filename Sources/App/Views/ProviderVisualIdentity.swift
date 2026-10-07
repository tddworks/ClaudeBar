import SwiftUI
import AppKit
import Kit
import Synchronization

// MARK: - Provider Visual Identity Protocol

/// Defines visual identity for AI providers.
/// Each concrete provider implements this to own its visual representation.
/// This keeps visual properties with the provider (rich domain) while
/// separating SwiftUI dependencies from the Domain layer.
///
/// `@MainActor` because the conformers are now main-actor-isolated providers and every
/// witness is SwiftUI-facing (`Color`/`LinearGradient`, read from views on the main actor).
@MainActor
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

// MARK: - Provider Visual Identity

/// A provider that is data takes its face from its definition's profile.
extension Account: ProviderVisualIdentity {
    public var symbolIcon: String { look.symbol ?? ProviderVisualIdentityLookup.symbolIcon(for: id) }

    public var iconAssetName: String { look.icon ?? ProviderVisualIdentityLookup.iconAssetName(for: id) }

    public func themeColor(for scheme: ColorScheme) -> Color {
        look.color.map { $0.color(for: scheme) } ?? ProviderVisualIdentityLookup.color(for: id, scheme: scheme)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        look.gradient(for: scheme) ?? ProviderVisualIdentityLookup.gradient(for: id, scheme: scheme)
    }
}

extension ProviderLook.Shades {
    func color(for scheme: ColorScheme) -> Color {
        let rgb = scheme == .dark ? dark : light
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension ProviderLook {
    /// The provider's colour running into `gradientEnd`, top-leading to bottom-trailing.
    func gradient(for scheme: ColorScheme) -> LinearGradient? {
        guard let color, let gradientEnd else { return nil }
        return LinearGradient(
            colors: [color.color(for: scheme), gradientEnd.color(for: scheme)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Static Provider Identity Lookup

/// Static helpers to look up provider visual identity by ID string.
/// Used by views that only have a providerId, not the login itself.
enum ProviderVisualIdentityLookup {
    /// Returns `name` when it names an SF Symbol available on this system.
    static func validSymbol(_ name: String?) -> String? {
        guard let name, !name.isEmpty,
              NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
        return name
    }

    /// Get provider theme color by ID
    /// The look a definition gives, for screens that only hold an id.
    private static func look(for providerId: String, in kit: ClaudeBarCore = Kit.shared) -> ProviderLook? {
        kit.definition(lineupId: providerId)?.profile.look
    }

    static func color(for providerId: String, scheme: ColorScheme) -> Color {
        if let color = look(for: providerId)?.color { return color.color(for: scheme) }
        switch providerId {
        default:
            return BaseTheme.purpleVibrant
        }
    }

    /// Get provider gradient by ID
    static func gradient(for providerId: String, scheme: ColorScheme) -> LinearGradient {
        if let gradient = look(for: providerId)?.gradient(for: scheme) { return gradient }
        let primaryColor = color(for: providerId, scheme: scheme)
        let secondaryColor: Color

        switch providerId {
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
        if let icon = look(for: providerId)?.icon { return icon }
        switch providerId {
        default: return "QuestionIcon"
        }
    }

    /// Get provider display name by ID
    static func name(for providerId: String) -> String {
        if let definition = Kit.shared.definition(lineupId: providerId) { return definition.profile.name }
        switch providerId {
        default: return providerId.capitalized
        }
    }

    /// Get provider SF symbol icon by ID
    static func symbolIcon(for providerId: String, in kit: ClaudeBarCore = Kit.shared) -> String {
        // A symbol a person wrote (an extension's icon) must exist, or the question mark.
        validSymbol(look(for: providerId, in: kit)?.symbol) ?? "questionmark.circle.fill"
    }
}
