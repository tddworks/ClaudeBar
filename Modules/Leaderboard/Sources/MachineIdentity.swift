import Mockable

/// This machine, as the leaderboard may know it (design §2a, §6). Faked in
/// tests to stand for another machine.
@Mockable
public protocol MachineIdentity: Sendable {
    /// The machine's model as a device's label ("MacBook Pro"), never its
    /// computer name; what the platform calls the machine when its model can't
    /// be read.
    var model: DeviceLabel { get }
}
