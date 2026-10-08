import Foundation

/// What a fetch case says about itself — *Import*'s "sends your key to" and
/// "runs", and *CLI location*. Each case answers for its own payload, so
/// nothing outside this file switches over the cases but the factory.
public protocol Connection: Sendable {
    /// Every URL a request may go to, as written — `{{setting.x}}` and
    /// `{{token}}` left for the caller to expand.
    var urls: [String] { get }
    /// Every command it may run, as argv.
    var commands: [[String]] { get }
}

extension Fetch {
    /// The case's payload, answering for itself.
    public var connection: any Connection {
        switch self {
        case .http(let request): request
        case .httpSteps(let steps): steps
        case .jsonRpc(let call): call
        case .cli(let call): call
        case .command(let call): call
        case .file(let call): call
        case .localServer(let call): call
        case .cloudWatch(let call): call
        case .directory(let call): call
        case .sqlite(let call): call
        case .script(let call): call
        }
    }

    /// The same fetch with the CLI at `binary` wherever it ran `cli` —
    /// *CLI location* (#210). Unchanged when it runs no such CLI.
    public func runningCLI(_ cli: String, at binary: String) -> Fetch {
        switch self {
        case .jsonRpc(let call) where call.cli == cli: .jsonRpc(call.running(binary))
        case .cli(let call) where call.cli == cli: .cli(call.running(binary))
        case .command(let call) where call.cli == cli: .command(call.running(binary))
        default: self
        }
    }
}

extension HTTPRequest: Connection {
    public var urls: [String] { [url] }
    public var commands: [[String]] { [] }
}

extension HTTPSteps: Connection {
    public var urls: [String] { steps.map(\.request.url) }
    public var commands: [[String]] { [] }
}

extension LocalServerCall: Connection {
    /// Only this Mac's loopback address, on whatever port the app listens.
    public var urls: [String] { paths.map { "https://127.0.0.1:{{port}}\($0)" } }
    public var commands: [[String]] {
        [LocalServerFetcher.processQuery(process), ["/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "{{pid}}"]]
    }
}

extension CloudWatchCall: Connection {
    /// The cloud's own SDK, signed with the person's profile — no key of ours.
    public var urls: [String] { [] }
    public var commands: [[String]] { [] }
}

extension ScriptCall: Connection {
    public var urls: [String] { [] }
    /// The person's own script — *Import* shows it before anything runs.
    public var commands: [[String]] { [["/bin/sh", "-c", run]] }
}

extension DirectoryCall: Connection {
    public var urls: [String] { [] }
    public var commands: [[String]] { [] }
}

extension SQLiteCall: Connection {
    /// An app's own database on this Mac — no host, nothing run.
    public var urls: [String] { [] }
    public var commands: [[String]] { [] }
}

extension FileCall: Connection {
    public var urls: [String] { [] }
    public var commands: [[String]] { [] }
}

extension JSONRPCCall: Connection {
    public var urls: [String] { [] }
    public var commands: [[String]] { [[cli] + args] }

    func running(_ binary: String) -> JSONRPCCall {
        JSONRPCCall(cli: binary, args: args, workingDirectory: workingDirectory, handshake: handshake,
                    call: call, params: params, then: then, environment: environment, timeout: timeout)
    }
}

extension CommandCall: Connection {
    public var urls: [String] { [] }
    public var commands: [[String]] { [[cli] + args] }

    func running(_ binary: String) -> CommandCall {
        CommandCall(cli: binary, args: args, input: input, timeout: timeout, workingDirectory: workingDirectory, environment: environment)
    }
}

extension CLICall: Connection {
    public var urls: [String] { [] }
    public var commands: [[String]] { [[cli] + args] }

    func running(_ binary: String) -> CLICall {
        CLICall(cli: binary, args: args, input: input, timeout: timeout, workingDirectory: workingDirectory,
                        autoResponses: autoResponses, environment: environment, readyWhen: readyWhen,
                        screen: screen, session: session, inputDelay: inputDelay)
    }
}

extension CredentialLookup {
    /// Repoints a credential refresh that runs `cli` at `binary`, through
    /// the lookups that wrap it — the same move `Fetch.runningCLI` makes.
    public func runningCLI(_ cli: String, at binary: String) -> CredentialLookup {
        switch self {
        case .firstOf(let lookups): .firstOf(lookups.map { $0.runningCLI(cli, at: binary) })
        case .refined(let base, let rules): .refined(base.runningCLI(cli, at: binary), rules)
        case .refreshing(let base, .cli(let call)):
            .refreshing(base.runningCLI(cli, at: binary), .cli(call.cli == cli ? call.running(binary) : call))
        case .refreshing(let base, let refresh): .refreshing(base.runningCLI(cli, at: binary), refresh)
        default: self
        }
    }
}
