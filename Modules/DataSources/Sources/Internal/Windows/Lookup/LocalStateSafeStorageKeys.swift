#if os(Windows)
import Crypto
import Foundation
import WinSDK

/// Windows' safeStorage, as Chromium's `OSCrypt` keeps it for an Electron app:
/// a 256-bit key in the app's `Local State` (`os_crypt.encrypted_key`, base64
/// of `DPAPI` and a blob only this Windows user can unprotect), and a value
/// sealed as `v10`, a 12-byte nonce, then AES-256-GCM's ciphertext and tag.
/// Unprotecting puts up no dialog.
struct LocalStateSafeStorageKeys: SafeStorageKeys {
    /// The folder apps keep their data in, `%APPDATA%`; the app's own is the
    /// folder named after it, as Electron's `userData` is.
    let applicationData: @Sendable () -> URL

    func key(app: String) throws -> Data {
        let file = applicationData().appendingPathComponent(app, isDirectory: true)
            .appendingPathComponent("Local State")
        let unreadable = SafeStorageKeyUnreadable(place: "\(app)'s Local State")
        guard let data = try? Data(contentsOf: file),
              let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let crypt = state["os_crypt"] as? [String: Any],
              let encoded = crypt["encrypted_key"] as? String,
              let wrapped = Data(base64Encoded: encoded), wrapped.starts(with: Self.dpapi),
              let key = Self.unprotect(wrapped.dropFirst(Self.dpapi.count)), key.count == 32
        else { throw unreadable }
        return key
    }

    func open(_ sealed: Data, with key: Data) -> Data? {
        guard sealed.starts(with: Self.version), sealed.count >= Self.version.count + 12 + 16,
              let box = try? AES.GCM.SealedBox(combined: sealed.dropFirst(Self.version.count))
        else { return nil }
        return try? AES.GCM.open(box, using: SymmetricKey(data: key))
    }

    private static let version = Data("v10".utf8)
    private static let dpapi = Data("DPAPI".utf8)

    /// `blob` unprotected for this Windows user; `nil` when DPAPI refuses it.
    static func unprotect(_ blob: Data) -> Data? {
        var bytes = [UInt8](blob)
        return bytes.withUnsafeMutableBufferPointer { bytes in
            var input = DATA_BLOB(cbData: DWORD(bytes.count), pbData: bytes.baseAddress)
            var output = DATA_BLOB()
            guard CryptUnprotectData(&input, nil, nil, nil, nil, 0, &output), let plain = output.pbData else { return nil }
            defer { LocalFree(plain) }
            return Data(bytes: plain, count: Int(output.cbData))
        }
    }
}
#endif
