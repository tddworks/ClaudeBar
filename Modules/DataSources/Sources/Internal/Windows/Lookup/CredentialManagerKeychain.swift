#if os(Windows)
import Diagnostics
import Foundation
import WinSDK

/// Windows' secret store: Credential Manager, asked as go-keyring asks it,
/// the library the GitHub CLI keeps its login with there. An item is a
/// generic credential named `service:account`, `service:` when there is no
/// account, its blob the password's UTF-8 bytes; a save keeps it on this PC
/// only (`CRED_PERSIST_LOCAL_MACHINE`), as go-keyring and the leaderboard's
/// key store (#547) do.
///
/// One call at a time, across the process: when several threads change items
/// at once, Credential Manager answers each change as made and keeps only
/// some. On a Windows 11 PC, 16 threads saving, overwriting and deleting items
/// of their own left 51 to 72 of 640 items behind that had been deleted; none
/// with the calls serialised. Providers refreshing together do exactly that.
struct CredentialManagerKeychain: KeychainItems {
    /// Held for every Credential Manager call this store makes.
    static let oneAtATime = NSLock()

    func password(service: String, account: String?) -> String? {
        let target = Self.target(service, account)
        var credential: PCREDENTIALW?
        let found = Self.oneAtATime.withLock {
            target.withCString(encodedAs: UTF16.self) { CredReadW($0, DWORD(CRED_TYPE_GENERIC), 0, &credential) }
        }
        guard found, let credential else {
            let error = GetLastError()
            if error != DWORD(ERROR_NOT_FOUND) { Self.logFailure("read", error) }
            return nil
        }
        defer { CredFree(credential) }
        guard let blob = credential.pointee.CredentialBlob else { return "" }
        return String(decoding: UnsafeBufferPointer(start: blob, count: Int(credential.pointee.CredentialBlobSize)), as: UTF8.self)
    }

    func save(_ password: String, service: String, account: String?) -> Bool {
        var name = Array(Self.target(service, account).utf16) + [0]
        var user = Array((account ?? "").utf16) + [0]
        var blob = Array(password.utf8)
        let saved = name.withUnsafeMutableBufferPointer { name in
            user.withUnsafeMutableBufferPointer { user in
                blob.withUnsafeMutableBufferPointer { blob in
                    var credential = CREDENTIALW()
                    credential.`Type` = DWORD(CRED_TYPE_GENERIC)
                    credential.TargetName = name.baseAddress
                    credential.UserName = account == nil ? nil : user.baseAddress
                    credential.CredentialBlobSize = DWORD(blob.count)
                    credential.CredentialBlob = blob.baseAddress
                    credential.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                    return Self.oneAtATime.withLock { CredWriteW(&credential, 0) }
                }
            }
        }
        if !saved { Self.logFailure("save", GetLastError()) }
        return saved
    }

    /// go-keyring's name for an item: its service and account, joined.
    private static func target(_ service: String, _ account: String?) -> String {
        service + ":" + (account ?? "")
    }

    private static func logFailure(_ operation: String, _ error: DWORD) {
        AppLog.credentials.error("Credential Manager \(operation) failed with error \(error)")
    }
}
#endif
