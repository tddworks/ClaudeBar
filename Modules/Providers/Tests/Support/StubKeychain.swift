import DataSources
import Foundation

/// A secret store answering each read as a test says, keeping nothing saved:
/// what a provider test hands the factory as this machine's Keychain.
struct StubKeychain: KeychainItems {
    let answer: @Sendable (_ service: String, _ account: String?) -> String?

    init(_ answer: @escaping @Sendable (_ service: String, _ account: String?) -> String?) {
        self.answer = answer
    }

    func password(service: String, account: String?) -> String? { answer(service, account) }

    func save(_ password: String, service: String, account: String?) -> Bool { false }
}
