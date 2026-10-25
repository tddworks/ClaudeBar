#if os(Windows)
import DataSources
import Diagnostics
import Foundation
import WinSDK

/// The key in Windows Credential Manager: a generic credential, its blob the
/// key's raw bytes, kept on this PC only (`CRED_PERSIST_LOCAL_MACHINE`): other
/// sessions of the same person on this PC read it, and it never roams to
/// another PC with the account. There is no plain-file fallback. Each call is
/// made `CredentialManager.oneAtATime`, with the provider logins' store: a
/// key saved while a login is refreshed must not be lost.
struct CredentialManagerSigningKeyStore: SigningKeyStore {
    var target = "com.tddworks.claudebar/leaderboard-signing-key"

    func load() -> Data? {
        var credential: PCREDENTIALW?
        let found = CredentialManager.oneAtATime {
            target.withCString(encodedAs: UTF16.self) { CredReadW($0, DWORD(CRED_TYPE_GENERIC), 0, &credential) }
        }
        guard found, let credential else {
            let error = GetLastError()
            if error != DWORD(ERROR_NOT_FOUND) { logFailure("read", error) }
            return nil
        }
        defer { CredFree(credential) }
        guard let blob = credential.pointee.CredentialBlob else { return nil }
        return Data(bytes: blob, count: Int(credential.pointee.CredentialBlobSize))
    }

    func save(_ rawKey: Data) {
        var name = Array(target.utf16) + [0]
        var blob = [UInt8](rawKey)
        let saved = name.withUnsafeMutableBufferPointer { name in
            blob.withUnsafeMutableBufferPointer { blob in
                var credential = CREDENTIALW()
                credential.`Type` = DWORD(CRED_TYPE_GENERIC)
                credential.TargetName = name.baseAddress
                credential.CredentialBlobSize = DWORD(blob.count)
                credential.CredentialBlob = blob.baseAddress
                credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                return CredentialManager.oneAtATime { CredWriteW(&credential, 0) }
            }
        }
        guard saved else { return logFailure("save", GetLastError()) }
    }

    func delete() {
        let deleted = CredentialManager.oneAtATime {
            target.withCString(encodedAs: UTF16.self) { CredDeleteW($0, DWORD(CRED_TYPE_GENERIC), 0) }
        }
        guard deleted else {
            let error = GetLastError()
            if error != DWORD(ERROR_NOT_FOUND) { logFailure("delete", error) }
            return
        }
    }

    private func logFailure(_ operation: String, _ error: DWORD) {
        AppLog.credentials.error("Credential Manager \(operation) failed with error \(error)")
    }
}
#endif
