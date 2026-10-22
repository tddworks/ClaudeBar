#if os(Linux)
import Foundation

/// This machine as the leaderboard knows it: "Linux", and its firmware's
/// system UUID. The model `/sys` reports is no label: a self-built machine
/// reports its motherboard, as on Windows, so it isn't read. Neither is the
/// computer's hostname, often a person's, nor `/etc/machine-id`, which a
/// cloned disk image carries to another machine.
struct LinuxMachineIdentity: MachineIdentity {
    var model: DeviceLabel { DeviceLabel("Linux")! }

    /// The SMBIOS system UUID, read from `/sys` each time, never from a file a
    /// copy brings along (design §2a). `nil` when `/sys` won't say — the file
    /// is often root-only, and firmware is allowed to leave the UUID unset —
    /// or when it holds a placeholder the board's maker left in.
    var hardwareUUID: String? {
        guard let text = try? String(contentsOfFile: Self.systemUUIDPath, encoding: .utf8) else { return nil }
        let uuid = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard UUID(uuidString: uuid) != nil, !SMBIOS.isPlaceholder(uuid) else { return nil }
        return uuid
    }

    /// The kernel's copy of the SMBIOS type 1 structure's system UUID, the
    /// same value `dmidecode -s system-uuid` prints.
    private static let systemUUIDPath = "/sys/class/dmi/id/product_uuid"
}
#endif
