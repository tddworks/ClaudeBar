import Foundation
import Quotas

/// A fetch or lookup case whose connection the platform has none of
/// (MODULAR_DESIGN §10: not a stub). It fails at its step, naming the case
/// and the platform, rather than finding nothing.
struct Unavailable: Fetching, CredentialFinding {
    let step: DataSourceError.Step
    /// The case, as a person reads it: "Reading a browser's cookies".
    let what: String
    /// The platform's `name`.
    let platform: String

    init(_ step: DataSourceError.Step, _ what: String, on platform: String) {
        self.step = step
        self.what = what
        self.platform = platform
    }

    /// Ready, so the case is tried and says why it can't run.
    func isReady() -> Bool { true }

    func fetch(with credential: Credential?) async throws -> Response { throw error }

    func find() throws -> FoundCredential? { throw error }

    var error: DataSourceError {
        DataSourceError(step, .executionFailed("\(what) isn't available on \(platform) yet."))
    }
}
