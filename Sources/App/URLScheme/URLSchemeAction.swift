import Foundation

/// What a `claudebar://` URL asks the app to do.
///
/// Only the exact documented URLs are actions: `claudebar://open`,
/// `claudebar://refresh`, `claudebar://settings`, and their three-slash
/// spelling (`claudebar:///open`). The URL is compared as a whole string, so
/// anything else, whether a parameter, a fragment, a user, a port or an extra
/// path, is not an action. `claudebar://use?provider=claude&account=work`
/// is the one with parameters: exactly those two, each once. See
/// docs/features/app/url-schemes/README.md.
enum URLSchemeAction: Equatable, Sendable {
    case open
    case refresh
    case settings
    /// *In use* — new terminal sessions of `provider` start on `account`
    /// (its name, email or `default`).
    case use(provider: String, account: String)

    static let scheme = "claudebar"

    private static let plain: [String: URLSchemeAction] = ["open": .open, "refresh": .refresh, "settings": .settings]

    /// For the log: the action, never its parameters.
    var name: String {
        switch self {
        case .open: "open"
        case .refresh: "refresh"
        case .settings: "settings"
        case .use: "use"
        }
    }

    init?(url: URL) {
        let string = url.absoluteString
        let lowered = string.lowercased()
        for (name, action) in Self.plain where ["\(Self.scheme)://\(name)", "\(Self.scheme):///\(name)"].contains(lowered) {
            self = action
            return
        }
        guard let use = Self.use(string) else { return nil }
        self = use
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
}
