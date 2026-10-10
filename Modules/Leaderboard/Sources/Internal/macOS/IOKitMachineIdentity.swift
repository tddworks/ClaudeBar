#if os(macOS)
import Foundation
import IOKit

/// The Mac read through the I/O Registry: its model, live from the hardware's
/// registry, never the computer name the person gave it.
struct IOKitMachineIdentity: MachineIdentity {
    var model: DeviceLabel {
        let name = MacModel.name(productName: Self.string(at: "IODeviceTree:/product", "product-name"),
                                 identifier: Self.platformString("model"))
        return DeviceLabel(name) ?? DeviceLabel(String(name.prefix(40))) ?? DeviceLabel("Mac")!
    }

    private static func platformString(_ key: String) -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return string(of: service, key)
    }

    private static func string(at path: String, _ key: String) -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        return string(of: entry, key)
    }

    /// A registry property as text: it is kept as NUL-terminated bytes.
    private static func string(of entry: io_registry_entry_t, _ key: String) -> String? {
        let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        if let text = value as? String { return text }
        guard let data = value as? Data else { return nil }
        return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }
}
#endif
