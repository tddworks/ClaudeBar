#if os(macOS)
import CommonCrypto
import Foundation

/// The Mac's safeStorage, as Chromium's `OSCrypt` keeps it for an Electron
/// app: a password in the app's Keychain item `"<app> Safe Storage"`, stretched
/// into an AES-128 key (PBKDF2-SHA1, salt `saltysalt`, 1003 rounds), and a
/// value sealed as `v10` then AES-128-CBC with a 16-space IV.
///
/// The item is the app's, so reading it through `security` can put up macOS's
/// access dialog; `SafeStorage` keeps the key so that happens once a launch.
struct KeychainSafeStorageKeys: SafeStorageKeys {
    var keychain: any KeychainItems = SecurityKeychain()

    func key(app: String) throws -> Data {
        let service = "\(app) Safe Storage"
        // By service alone: Electron names the account after the app too, but
        // the service is what the app's own reads go by.
        guard let stored = keychain.password(service: service, account: nil),
              case let password = Credential.trimmed(stored), !password.isEmpty
        else { throw SafeStorageKeyUnreadable(place: "Keychain “\(service)”") }
        return Self.derive(password)
    }

    func open(_ sealed: Data, with key: Data) -> Data? {
        guard sealed.starts(with: Self.version) else { return nil }
        let ciphertext = sealed.dropFirst(Self.version.count)
        var plain = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var written = 0
        let status = plain.withUnsafeMutableBytes { plain in
            ciphertext.withUnsafeBytes { ciphertext in
                key.withUnsafeBytes { key in
                    Self.iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, key.count, iv.baseAddress,
                                ciphertext.baseAddress, ciphertext.count,
                                plain.baseAddress, plain.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return plain.prefix(written)
    }

    private static let version = Data("v10".utf8)
    private static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

    private static func derive(_ password: String) -> Data {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        _ = key.withUnsafeMutableBytes { key in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count,
                                     salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                     key.bindMemory(to: UInt8.self).baseAddress, key.count)
            }
        }
        return key
    }
}
#endif
