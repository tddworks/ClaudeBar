import Mockable

/// This machine, as the leaderboard may know it (design §2a, §6). Faked in
/// tests to stand for another machine.
@Mockable
public protocol MachineIdentity: Sendable {
    /// The machine's model as a device's label ("MacBook Pro"), never its
    /// computer name; what the platform calls the machine when its model can't
    /// be read.
    var model: DeviceLabel { get }
    /// The machine's hardware UUID, read live from the hardware (a Mac's
    /// `IOPlatformUUID`, a PC's SMBIOS system UUID), never from a file, so a
    /// copy of the app's data brings the key but not this. `nil` when it
    /// can't be read, or reads as a placeholder a board's maker left in.
    /// Never sent: only its hash, salted with the key, is kept.
    var hardwareUUID: String? { get }
}
