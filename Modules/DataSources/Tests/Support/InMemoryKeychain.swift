import Foundation
@testable import DataSources

/// A secret store in memory, for a reader's tests: one item per service and
/// account exactly as asked, "no account" being an item of its own, as a store
/// whose adapter names it the same way for a read and a save.
final class InMemoryKeychain: KeychainItems, @unchecked Sendable {
    struct Name: Hashable {
        let service: String
        let account: String?
    }

    private let lock = NSLock()
    private var items: [Name: String]
    private var saved: [Name] = []

    init(_ items: [Name: String] = [:]) {
        self.items = items
    }

    /// One item, `password` under `service` and `account`.
    convenience init(service: String, account: String? = nil, password: String) {
        self.init([Name(service: service, account: account): password])
    }

    func password(service: String, account: String?) -> String? {
        lock.withLock { items[Name(service: service, account: account)] }
    }

    func save(_ password: String, service: String, account: String?) -> Bool {
        lock.withLock {
            let name = Name(service: service, account: account)
            items[name] = password
            saved.append(name)
        }
        return true
    }

    /// Every item, by name.
    var all: [Name: String] { lock.withLock { items } }
    /// The names saved to, in order.
    var saves: [Name] { lock.withLock { saved } }
}
