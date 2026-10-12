#if os(Windows)
import Foundation
import WinSDK

extension Platform {
    /// Windows: the key in Credential Manager, kept on this PC; the PC labelled
    /// as `WindowsMachineIdentity` says.
    static let current = Platform(
        deviceName: "PC",
        signingKeyStore: CredentialManagerSigningKeyStore(),
        machineIdentity: WindowsMachineIdentity()
    )
}

/// This PC as the leaderboard knows it: "Windows PC", and its firmware's
/// system UUID. The model Windows reports is no label: a self-built PC
/// reports its motherboard ("Z790 UD AC"), so it isn't read. Neither is the
/// computer's name, often a person's, nor the machine GUID, which is a
/// registry value a cloned disk image carries to another PC.
struct WindowsMachineIdentity: MachineIdentity {
    var model: DeviceLabel { DeviceLabel("Windows PC")! }

    /// The SMBIOS system UUID, read from the firmware table each time, never
    /// from the registry: a disk image restored to another PC brings the key
    /// and the hash but not this (design §2a). `nil` when the table has none,
    /// or holds a placeholder the board's maker left in.
    var hardwareUUID: String? {
        Self.firmwareTable().flatMap(SMBIOS.systemUUID(in:))
    }

    /// `GetSystemFirmwareTable('RSMB')`: the raw SMBIOS table.
    private static func firmwareTable() -> Data? {
        let provider = DWORD(0x5253_4D42) // 'RSMB'
        let size = GetSystemFirmwareTable(provider, 0, nil, 0)
        guard size > 0 else { return nil }
        var table = Data(count: Int(size))
        let read = table.withUnsafeMutableBytes { GetSystemFirmwareTable(provider, 0, $0.baseAddress, size) }
        guard read > 0, read <= size else { return nil }
        return table.prefix(Int(read))
    }
}
#endif
