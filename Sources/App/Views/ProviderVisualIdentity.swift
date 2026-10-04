import SwiftUI
import AppKit
import Domain
import Providers
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
    private var look: ProviderLook { provider.definition.profile.look }

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

// MARK: - ExtensionProvider Visual Identity

extension ExtensionProvider: ProviderVisualIdentity {
    public var symbolIcon: String {
        ProviderVisualIdentityLookup.validSymbol(manifest.icon) ?? "questionmark.circle.fill"
    }

    /// Extensions have no bundled asset, so views always take the SF Symbol path.
    public var iconAssetName: String { "" }

    public func themeColor(for scheme: ColorScheme) -> Color {
        ProviderVisualIdentityLookup.color(for: id, scheme: scheme)
    }

    public func themeGradient(for scheme: ColorScheme) -> LinearGradient {
        ProviderVisualIdentityLookup.gradient(for: id, scheme: scheme)
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
    /// SF Symbols declared by extension manifests, keyed by provider id (`ext-<manifest.id>`).
    /// Consulted only after the built-in tables, so an extension can never restyle a built-in provider.
    private static let extensionSymbols = Mutex<[String: String]>([:])

    /// Records the manifest icons of loaded extensions so id-only call sites can draw them.
    /// Icons that are empty or not a known SF Symbol are skipped and keep the question mark.
    @MainActor
    static func registerExtensionIcons(from providers: [ExtensionProvider]) {
        let declared = providers.map { ($0.id, validSymbol($0.manifest.icon)) }
        extensionSymbols.withLock { symbols in
            for (id, symbol) in declared {
                symbols[id] = symbol
            }
        }
    }

    /// Returns `name` when it names an SF Symbol available on this system.
    static func validSymbol(_ name: String?) -> String? {
        guard let name, !name.isEmpty,
              NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
        return name
    }

    /// Get provider theme color by ID
    /// The look a definition gives, for screens that only hold an id.
    private static func look(for providerId: String) -> ProviderLook? {
        Providers.definition(forLineupId: providerId)?.profile.look
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
        if let definition = Providers.definition(forLineupId: providerId) { return definition.profile.name }
        switch providerId {
        default: return providerId.capitalized
        }
    }

    /// Get provider SF symbol icon by ID
    static func symbolIcon(for providerId: String) -> String {
        if let symbol = look(for: providerId)?.symbol { return symbol }
        switch providerId {
        default:
            return extensionSymbols.withLock { $0[providerId] } ?? "questionmark.circle.fill"
        }
    }
}
