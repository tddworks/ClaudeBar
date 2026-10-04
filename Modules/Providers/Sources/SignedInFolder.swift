import Foundation

/// *Signed-in Folder* — where an added login lives: the folder its CLI keeps
/// its key in, and who made it. A folder the person chose is theirs, and
/// their terminal may still use it; a folder ClaudeBar made for *Sign in
/// with browser* is ClaudeBar's, and nothing else uses it.
public struct SignedInFolder: Sendable, Equatable {
    public let url: URL
    public let madeBy: AccountOrigin

    /// Where *Sign in with browser* makes its folders: `<provider>/<uuid>`.
    public static let signInRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claudebar/accounts", isDirectory: true)

    public init(url: URL, madeBy: AccountOrigin) {
        self.url = url.standardizedFileURL
        self.madeBy = madeBy
    }

    /// A new folder for one sign-in to `providerId`.
    public static func forSignIn(to providerId: String, under root: URL = signInRoot) -> SignedInFolder {
        SignedInFolder(
            url: root.appendingPathComponent(providerId, isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true),
            madeBy: .signIn
        )
    }

    /// Whether *Remove* takes the folder with the account: only one ClaudeBar
    /// made by signing in, named as it names them. A live refresh token left
    /// behind would be a login nobody can see.
    public var goesWithAccount: Bool {
        madeBy == .signIn && UUID(uuidString: url.lastPathComponent) != nil
    }
}
