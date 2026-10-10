import Foundation

/// The factory (MODULAR_DESIGN §4): the board's server, where this machine
/// keeps the key, and the machine itself. A client builds
/// `LeaderboardMembership`, `LeaderboardUploader` and `Board` over them.
public enum Leaderboard {
    /// The board's server over HTTPS. `client` is how the app names itself on
    /// every request (`X-Client`), such as `claudebar-macos/0.5.11`, so the
    /// server can tell clients apart and refuse one broken version alone.
    public static func makeAPI(client: String) -> any LeaderboardAPI {
        LeaderboardHTTPClient(client: client)
    }

    /// Where this machine keeps the key's private half, or `nil` where
    /// ClaudeBar keeps none yet: Windows, until MODULAR_DESIGN §10's phase 3.
    public static func makeKeyStore() -> (any SigningKeyStore)? {
        Platform.current.signingKeyStore
    }

    /// This machine as the leaderboard knows it, or `nil` where ClaudeBar reads
    /// none yet: Windows, until MODULAR_DESIGN §10's phase 3.
    public static func makeMachineIdentity() -> (any MachineIdentity)? {
        Platform.current.machineIdentity
    }
}
