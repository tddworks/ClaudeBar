import Foundation

/// What this machine offers the leaderboard (MODULAR_DESIGN §10, "One place
/// picks the platform"): where it keeps the key's private half, and how it
/// reads the machine. Each platform folder defines `current` once; only the
/// factory reads it.
///
/// A `nil` connection means one thing: this platform has none yet.
struct Platform: Sendable {
    /// Where the key's private half is kept.
    var signingKeyStore: (any SigningKeyStore)?
    /// The machine, read from its hardware.
    var machineIdentity: (any MachineIdentity)?
}
