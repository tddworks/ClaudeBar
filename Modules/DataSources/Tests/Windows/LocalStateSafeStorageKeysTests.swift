#if os(Windows)
import Foundation
import Testing
import WinSDK
@testable import DataSources

/// Windows opens what an Electron app sealed with Chromium's scheme: the key
/// in the app's `Local State`, DPAPI-protected for this user, and AES-256-GCM
/// behind `v10`. The sealed value is the GCM spec's test case 14 (all-zero
/// key, nonce and plaintext), so it is made outside this code.
@Suite
struct LocalStateSafeStorageKeysTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let zeroKey = Data(count: 32)
    private let sealed = Data("v10".utf8) + Data(count: 12)
        + Data(hex: "cea7403d4d606b6e074ec5d3baf39d18") + Data(hex: "d0d1c8a799996bf0265b98b5d48ab919")

    private var keys: LocalStateSafeStorageKeys {
        let folder = folder
        return LocalStateSafeStorageKeys(applicationData: { folder })
    }

    /// `key` protected by DPAPI for this user, as Chromium writes it.
    private func writeLocalState(protecting key: Data) throws {
        var bytes = [UInt8](key)
        let blob = try bytes.withUnsafeMutableBufferPointer { bytes -> Data in
            var input = DATA_BLOB(cbData: DWORD(bytes.count), pbData: bytes.baseAddress)
            var output = DATA_BLOB()
            guard CryptProtectData(&input, nil, nil, nil, nil, 0, &output), let protected = output.pbData else {
                throw CocoaError(.fileWriteUnknown)
            }
            defer { LocalFree(protected) }
            return Data(bytes: protected, count: Int(output.cbData))
        }
        let state = #"{"os_crypt":{"encrypted_key":"\#((Data("DPAPI".utf8) + blob).base64EncodedString())"}}"#
        let app = folder.appendingPathComponent("Cursor", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(state.utf8).write(to: app.appendingPathComponent("Local State"))
    }

    @Test
    func `should open a value sealed with the key in the app's Local State`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeLocalState(protecting: zeroKey)

        let key = try keys.key(app: "Cursor")

        #expect(key == zeroKey)
        #expect(keys.open(sealed, with: key) == Data(count: 16))
    }

    @Test
    func `should not open a value with another key`() {
        #expect(keys.open(sealed, with: Data(repeating: 1, count: 32)) == nil)
    }

    @Test
    func `should name the app's Local State when it has none`() {
        #expect(throws: SafeStorageKeyUnreadable(place: "Cursor's Local State")) {
            try keys.key(app: "Cursor")
        }
    }
}

private extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}
#endif
