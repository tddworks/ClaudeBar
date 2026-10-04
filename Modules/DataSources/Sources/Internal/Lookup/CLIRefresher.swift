import Diagnostics
import Quotas
import Foundation

/// Renews a credential by running the CLI that owns it: started as a person
/// would, it renews its own login file. Only after the token was refused —
/// never ahead of time — and the file is read again, never written by us.
struct CLIRefresher: CredentialRefreshing {
    let call: CLICall
    let executor: any CLIExecutor

    var retryStatuses: [Int] { [401] }
    var writesBack: Bool { false }

    func isDue(_ credential: Credential) -> Bool { false }

    func refresh(_ credential: Credential) async throws -> Credential {
        guard executor.locate(call.cli) != nil else {
            AppLog.probes.info("\(call.cli) isn't installed, so its login can't be renewed")
            throw UsageError.authenticationRequired
        }
        AppLog.probes.info("Running \(call.cli) to renew its login")
        _ = try await executor.execute(binary: call.cli, args: call.args, input: call.input, timeout: call.timeout,
                                       workingDirectory: call.workingDirectory?.url, autoResponses: call.autoResponses)
        return credential
    }
}
