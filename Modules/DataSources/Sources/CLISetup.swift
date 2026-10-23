import Foundation

/// How a vendor's CLI runs for an added account (`accounts.cli`): variables
/// that point it at the account's folder and drop this Mac's login, and
/// arguments that keep the login inside the folder. Said once, laid over
/// every run of that CLI — a fetch, a renewal, a sign-in (#577).
///
/// `{ "environment": { "set": { "CODEX_HOME": "{{account.folder}}" },
///                     "unset": ["OPENAI_API_KEY"] },
///    "args": ["-c", "cli_auth_credentials_store=\"file\""] }`
public struct CLISetup: Sendable, Equatable, Codable {
    public let environment: ProcessEnvironment
    /// Put before the run's own arguments: the CLI's options, not a command's.
    public let args: [String]

    public init(environment: ProcessEnvironment = ProcessEnvironment(), args: [String] = []) {
        self.environment = environment
        self.args = args
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        environment = try container.decodeIfPresent(ProcessEnvironment.self, forKey: .environment) ?? ProcessEnvironment()
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
    }

    private enum CodingKeys: String, CodingKey { case environment, args }
}

extension ProcessEnvironment {
    /// This environment with `other` laid over it: both remove what they
    /// unset, `other`'s values and defaults win, and a variable either sets is
    /// never unset.
    public func overlaid(with other: ProcessEnvironment) -> ProcessEnvironment {
        let set = self.set.merging(other.set) { _, new in new }
        var seen = Set<String>()
        let unset = (self.unset + other.unset).filter { set[$0] == nil && seen.insert($0).inserted }
        return ProcessEnvironment(unset: unset, defaults: defaults.merging(other.defaults) { _, new in new }, set: set)
    }
}

extension Fetch {
    /// The same fetch, every run of `cli` set up as `setup` says.
    public func runningCLI(_ cli: String, with setup: CLISetup) -> Fetch {
        switch self {
        case .jsonRpc(let call) where call.cli == cli: .jsonRpc(call.set(up: setup))
        case .cli(let call) where call.cli == cli: .cli(call.set(up: setup))
        case .command(let call) where call.cli == cli: .command(call.set(up: setup))
        default: self
        }
    }
}

extension CredentialLookup {
    /// The same lookup, a renewal by `cli` set up as `setup` says.
    public func runningCLI(_ cli: String, with setup: CLISetup) -> CredentialLookup {
        switch self {
        case .firstOf(let lookups): .firstOf(lookups.map { $0.runningCLI(cli, with: setup) })
        case .refined(let base, let rules): .refined(base.runningCLI(cli, with: setup), rules)
        case .refreshing(let base, .cli(let call)):
            .refreshing(base.runningCLI(cli, with: setup), .cli(call.cli == cli ? call.set(up: setup) : call))
        case .refreshing(let base, let refresh): .refreshing(base.runningCLI(cli, with: setup), refresh)
        default: self
        }
    }
}

extension DataSourceDefinition {
    /// The data source with every run of `cli` — its fetch and its key's
    /// renewal — set up as `setup` says.
    public func runningCLI(_ cli: String, with setup: CLISetup) -> DataSourceDefinition {
        changing { parts in
            parts.fetch = parts.fetch.runningCLI(cli, with: setup)
            parts.credential = parts.credential?.runningCLI(cli, with: setup)
        }
    }

    /// The data source with the CLI at `binary` wherever it ran `cli` —
    /// *CLI location* (#210).
    public func runningCLI(_ cli: String, at binary: String) -> DataSourceDefinition {
        changing { parts in
            parts.fetch = parts.fetch.runningCLI(cli, at: binary)
            parts.credential = parts.credential?.runningCLI(cli, at: binary)
        }
    }
}

extension JSONRPCCall {
    func set(up setup: CLISetup) -> JSONRPCCall {
        JSONRPCCall(cli: cli, args: setup.args + args, workingDirectory: workingDirectory, handshake: handshake,
                    call: call, params: params, then: then, environment: environment.overlaid(with: setup.environment),
                    timeout: timeout, errors: errors)
    }
}

extension CommandCall {
    func set(up setup: CLISetup) -> CommandCall {
        CommandCall(cli: cli, args: setup.args + args, input: input, timeout: timeout, workingDirectory: workingDirectory,
                    environment: environment.overlaid(with: setup.environment))
    }
}

extension CLICall {
    func set(up setup: CLISetup) -> CLICall {
        CLICall(cli: cli, args: setup.args + args, input: input, timeout: timeout, workingDirectory: workingDirectory,
                autoResponses: autoResponses, environment: environment.overlaid(with: setup.environment), readyWhen: readyWhen,
                screen: screen, session: session, inputDelay: inputDelay)
    }
}
extension CLISetup: DefinitionTemplate {}
