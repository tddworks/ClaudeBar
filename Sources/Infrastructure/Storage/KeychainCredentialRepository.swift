import Foundation
import Security
import Domain

/// Stores sensitive credentials as generic-password items in the user's Keychain.
public final class KeychainCredentialRepository: CredentialRepository, @unchecked Sendable {
    /// Shared production credential store for ClaudeBar.
    public static let shared = KeychainCredentialRepository()

    private let service: String

    /// Creates a Keychain credential store with an isolated service name.
    /// - Parameter service: The Keychain service used to namespace credential items.
    public init(service: String = "com.tddworks.claudebar.credentials") {
        self.service = service
    }

    /// Saves or replaces a credential without logging its value.
    public func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)
        let update: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logFailure(operation: "update", status: updateStatus)
            return
        }

        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logFailure(operation: "save", status: addStatus)
        }
    }

    /// Retrieves a credential from Keychain, or nil when unavailable.
    public func get(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logFailure(operation: "read", status: status)
            }
            return nil
        }

        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes a credential from Keychain and reports whether it is absent.
    @discardableResult
    public func delete(forKey key: String) -> Bool {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }

        logFailure(operation: "delete", status: status)
        return false
    }

    /// Checks whether a credential can be retrieved from Keychain.
    public func exists(forKey key: String) -> Bool {
        get(forKey: key) != nil
    }

    private func baseQuery(forKey key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
    }

    private func logFailure(operation: String, status: OSStatus) {
        AppLog.credentials.error("Keychain credential \(operation) failed with status \(status)")
    }
}
