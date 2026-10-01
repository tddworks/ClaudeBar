import Foundation

/// What a `claudebar://` URL asks the app to do.
///
/// Only the exact documented URLs are actions: `claudebar://open`,
/// `claudebar://refresh`, `claudebar://settings`, and their three-slash
/// spelling (`claudebar:///open`). The URL is compared as a whole string, so
/// anything else, whether a parameter, a fragment, a user, a port or an extra
/// path, is not an action. See docs/features/url-schemes/README.md.
enum URLSchemeAction: String, Equatable, Sendable, CaseIterable {
    case open
    case refresh
    case settings

    static let scheme = "claudebar"

    /// The exact URL strings that name this action.
    var acceptedURLStrings: Set<String> {
        ["\(Self.scheme)://\(rawValue)", "\(Self.scheme):///\(rawValue)"]
    }

    init?(url: URL) {
        let string = url.absoluteString.lowercased()
        guard let action = Self.allCases.first(where: { $0.acceptedURLStrings.contains(string) }) else {
            return nil
        }
        self = action
    }
}
