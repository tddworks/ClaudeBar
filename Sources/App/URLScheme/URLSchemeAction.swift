import Foundation

/// What a `claudebar://` URL asks the app to do.
///
/// Only the exact documented URLs are actions: `claudebar://open`,
/// `claudebar://refresh`, `claudebar://settings`, and their three-slash
/// spelling (`claudebar:///open`). The URL is compared as a whole string, so
/// anything else, whether a parameter, a fragment, a user, a port or an extra
/// path, is not an action. `claudebar://use?provider=claude&account=work` and
/// `claudebar://show-anyway?provider=claude` are the ones with parameters:
/// exactly the documented ones, each once. See docs/features/app/url-schemes/README.md.
enum URLSchemeAction: Equatable, Sendable {
    case open
    case refresh
    case settings
    /// *In use* — new terminal sessions of `provider` start on `account`
    /// (its name, email or `default`).
    case use(provider: String, account: String)
    /// *Rest when empty* — draw a resting `provider` as usual, one click.
    case showAnyway(provider: String)

    static let scheme = "claudebar"

    private static let plain: [String: URLSchemeAction] = ["open": .open, "refresh": .refresh, "settings": .settings]

    /// For the log: the action, never its parameters.
    var name: String {
        switch self {
        case .open: "open"
        case .refresh: "refresh"
        case .settings: "settings"
        case .use: "use"
        case .showAnyway: "show-anyway"
        }
    }

    init?(url: URL) {
        let string = url.absoluteString
        let lowered = string.lowercased()
        for (name, action) in Self.plain where ["\(Self.scheme)://\(name)", "\(Self.scheme):///\(name)"].contains(lowered) {
            self = action
            return
        }
        guard let parameterised = Self.use(string) ?? Self.showAnyway(string) else { return nil }
        self = parameterised
    }

    /// `claudebar://use?provider=<id>&account=<name>`, and nothing more.
    private static func use(_ string: String) -> URLSchemeAction? {
        let prefixes = ["\(scheme)://use?", "\(scheme):///use?"]
        guard let prefix = prefixes.first(where: { string.lowercased().hasPrefix($0) }),
              !string.contains("#"),
              let items = URLComponents(string: "x:?" + string.dropFirst(prefix.count))?.queryItems,
              items.count == 2,
              let provider = items.first(where: { $0.name == "provider" })?.value,
              let account = items.first(where: { $0.name == "account" })?.value,
              Set(items.map(\.name)) == ["provider", "account"],
              provider.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil,
              !account.isEmpty, account.count <= 100,
              account.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return .use(provider: provider, account: account)
    }

    /// The link a *Rest when empty* notice's button opens — built here, beside
    /// the parser that reads it back, so the link has one owner.
    static func showAnywayLink(provider: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "show-anyway"
        components.queryItems = [URLQueryItem(name: "provider", value: provider)]
        return components.url!
    }

    /// `claudebar://show-anyway?provider=<id>`, and nothing more — *Rest when
    /// empty*'s one click. The id's shape is checked loosely — built-in,
    /// custom and extension ids differ, so only the unsafe is refused; the
    /// handler resolves the name against the registered products.
    private static func showAnyway(_ string: String) -> URLSchemeAction? {
        let prefixes = ["\(scheme)://show-anyway?", "\(scheme):///show-anyway?"]
        guard let prefix = prefixes.first(where: { string.lowercased().hasPrefix($0) }),
              !string.contains("#"),
              let items = URLComponents(string: "x:?" + string.dropFirst(prefix.count))?.queryItems,
              items.count == 1,
              let provider = items.first(where: { $0.name == "provider" })?.value,
              Set(items.map(\.name)) == ["provider"],
              !provider.isEmpty, provider.count <= 200,
              provider.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return .showAnyway(provider: provider)
    }
}
