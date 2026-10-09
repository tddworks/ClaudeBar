import Diagnostics
import Quotas
import Foundation
import Synchronization

/// Fills `{{name}}` from a credential. `nil` when a placeholder has no value,
/// so a header like `ChatGPT-Account-Id: {{account}}` is simply left out.
/// `{{token#jwt.sub}}` is a claim of the value, a JWT — read, not verified;
/// `{{baseURL#host}}` is the host of a URL value.
enum Template {
    /// `system.` names come from `system`; without one they stay unfilled.
    static func fill(_ text: String, with credential: Credential?, system: SystemValues? = nil) -> String? {
        var result = ""
        var rest = Substring(text)
        while let open = rest.range(of: "{{") {
            result += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "}}") else { return nil }
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            guard let value = value(of: name, in: credential, system: system) else { return nil }
            result += value
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    private static func value(of name: String, in credential: Credential?, system: SystemValues?) -> String? {
        if name.hasPrefix("system.") { return system?.value(String(name.dropFirst(7))) }
        if name.hasSuffix("#host") {
            return credential?[String(name.dropLast(5))].flatMap { URL(string: $0)?.host }
        }
        let parts = name.components(separatedBy: "#jwt.")
        guard let value = credential?[parts[0]] else { return nil }
        return parts.count == 2 ? CredentialDocument.claim(parts[1], in: value) : value
    }
}

extension Credential {
    /// The values as they go into a URL: `team & org` becomes `team%20%26%20org`,
    /// so a value can never add a query item or end the URL.
    var percentEncodedForURL: Credential {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return Credential(values.mapValues { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 })
    }
}

/// `http` — one HTTP request. 2xx answers with the response; anything else
/// becomes the `UsageError` a provider reports, keeping its status so a
/// refresh-and-retry can be tried.
struct HTTPFetcher: Fetching {
    let request: HTTPRequest
    let network: any NetworkClient
    let now: @Sendable () -> Date

    static let defaultRetryAfter: TimeInterval = 5 * 60

    func isReady() -> Bool { true }

    func fetch(with credential: Credential?) async throws -> Response {
        let system = SystemValues(now: now())
        guard let urlText = Template.fill(request.url, with: credential?.percentEncodedForURL, system: system), let url = URL(string: urlText) else {
            throw UsageError.executionFailed("Invalid URL")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        for (name, value) in request.headers {
            if let filled = Template.fill(value, with: credential, system: system) {
                urlRequest.setValue(filled, forHTTPHeaderField: name)
            }
        }
        if let body = request.body, let filled = Template.fill(body, with: credential, system: system) {
            urlRequest.httpBody = Data(filled.utf8)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await network.request(urlRequest)
        } catch {
            AppLog.probes.error("HTTP fetch failed: \(error.localizedDescription)")
            throw UsageError.executionFailed("Network error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.executionFailed("Invalid response")
        }

        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String {
                headers[name] = value
            }
        }

        // A 429 is always a rate limit, whatever a request accepts.
        if http.statusCode != 429, request.accepts(http.statusCode) {
            return Response(status: http.statusCode, headers: headers, body: data)
        }
        // The status is the fact; the definition's `errors` may word it.
        switch http.statusCode {
        case 401, 403:
            throw HTTPStatusError(status: http.statusCode, reason: .authenticationRequired)
        case 429:
            let wait = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After"), now: now()) ?? Self.defaultRetryAfter
            throw HTTPStatusError(status: 429, reason: .rateLimited(retryAt: now().addingTimeInterval(wait)))
        default:
            AppLog.probes.error("HTTP fetch: status \(http.statusCode)")
            throw HTTPStatusError(status: http.statusCode, reason: .executionFailed("HTTP error: \(http.statusCode)"))
        }
    }

    /// `Retry-After` as seconds, or as an HTTP date.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        // `0` or a negative wait is no answer: retrying at once would hammer the endpoint.
        if let seconds = TimeInterval(value) { return seconds > 0 ? seconds : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.timeZone = TimeZone(identifier: "GMT")
        guard let date = formatter.date(from: value), date > now else { return nil }
        return date.timeIntervalSince(now)
    }
}

/// `jsonRpc` — starts the CLI, sends the handshake, then the call, and
/// answers with the call's whole message as the response body.
struct JSONRPCFetcher: Fetching {
    let call: JSONRPCCall
    let cliExecutor: any CLIExecutor
    let makeTransport: DataSources.TransportFactory

    func isReady() -> Bool {
        if cliExecutor.locate(call.cli) != nil { return true }
        AppLog.probes.error("'\(call.cli)' not found in PATH")
        return false
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let directory = call.workingDirectory?.url
        let transport = try makeTransport(call.cli, call.args, Self.environment(call.environment), directory)
        defer { transport.close() }

        // A CLI can stall without answering or exiting (#517). A read from
        // its pipe ignores cancellation, so at the deadline, or when the
        // refresh is cancelled, the transport is closed: that stops the CLI
        // and ends the read.
        let deadline = Deadline()
        do {
            return try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Response?.self) { group in
                    group.addTask { try await exchange(over: transport) }
                    group.addTask {
                        try await Task.sleep(for: .seconds(call.timeout))
                        deadline.pass()
                        transport.close()
                        return nil
                    }
                    while let answered = try await group.next() {
                        if let response = answered {
                            group.cancelAll()
                            return response
                        }
                    }
                    throw UsageError.timeout
                }
            } onCancel: {
                transport.close()
            }
        } catch where deadline.hasPassed {
            AppLog.probes.error("\(call.cli) \(call.call) did not answer within \(Int(call.timeout))s")
            throw UsageError.timeout
        }
    }

    private func exchange(over transport: any RPCTransport) async throws -> Response {
        let session = RPCSession(transport: transport, errors: call.errors)
        for step in call.handshake {
            if let method = step.request {
                _ = try await session.request(method, params: step.params)
            } else if let method = step.notify {
                try session.notify(method, params: step.params)
            }
        }
        var message = try await session.request(call.call, params: call.params)
        for followUp in call.then {
            message[followUp.as] = try await session.request(followUp.request, params: followUp.params)
        }
        AppLog.probes.debug("\(call.cli) \(call.call) answered")
        return Response(body: try JSONSerialization.data(withJSONObject: message))
    }

    /// The app's environment changed as the call asks, or `nil` to inherit it
    /// untouched. Each process gets its own; the app's is never mutated.
    static func environment(_ change: ProcessEnvironment) -> [String: String]? {
        guard !change.unset.isEmpty || !change.set.isEmpty else { return nil }
        var environment = ProcessInfo.processInfo.environment
        for name in change.unset { environment.removeValue(forKey: name) }
        environment.merge(change.set) { _, new in new }
        return environment
    }
}

/// Whether a JSON-RPC exchange ran out of time — set by its timer, read by
/// the fetch.
private final class Deadline: Sendable {
    private let passed = Mutex(false)

    func pass() { passed.withLock { $0 = true } }
    var hasPassed: Bool { passed.withLock { $0 } }
}

/// Newline-delimited JSON-RPC over a transport: numbered requests, answers
/// matched by id, notifications skipped.
final class RPCSession: @unchecked Sendable {
    private let transport: any RPCTransport
    private let errors: [TextMapping.ErrorRule]
    private var nextID = 1

    init(transport: any RPCTransport, errors: [TextMapping.ErrorRule] = []) {
        self.transport = transport
        self.errors = errors
    }

    func request(_ method: String, params: JSONValue?) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send(["id": id, "method": method, "params": params?.foundationObject ?? [String: Any]()])
        while true {
            let data = try await transport.receive()
            guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let messageID = message["id"] as? Int, messageID == id else {
                continue
            }
            if let error = message["error"] as? [String: Any], let text = error["message"] as? String {
                if let rule = errors.first(where: { $0.matches(text) }) { throw rule.error.usageError }
                throw UsageError.executionFailed("RPC error: \(text)")
            }
            return message
        }
    }

    func notify(_ method: String, params: JSONValue?) throws {
        try send(["method": method, "params": params?.foundationObject ?? [String: Any]()])
    }

    private func send(_ payload: [String: Any]) throws {
        try transport.send(try JSONSerialization.data(withJSONObject: payload))
    }
}

/// `command` — runs a command over pipes and answers with what it printed. A
/// missing CLI, a non-zero exit and a failed launch are reported as facts the
/// definition's `errors` may word.
struct CommandFetcher: Fetching {
    /// The executor for a command with this environment.
    typealias MakeExecutor = @Sendable (ProcessEnvironment) -> any CLIExecutor

    let call: CommandCall
    let makeExecutor: MakeExecutor

    func isReady() -> Bool {
        makeExecutor(call.environment).locate(call.cli) != nil
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let environment = try call.environment.filled(with: credential)
        let executor = makeExecutor(environment)
        guard executor.locate(call.cli) != nil else { throw CLIMissingError(cli: call.cli) }
        let result: CLIResult
        do {
            result = try await executor.execute(
                binary: call.cli,
                args: call.args,
                input: call.input,
                timeout: call.timeout,
                workingDirectory: call.workingDirectory?.url,
                autoResponses: [:]
            )
        } catch UsageError.cliNotFound {
            // Gone between the check and the run.
            throw CLIMissingError(cli: call.cli)
        } catch let error as UsageError {
            throw error
        } catch {
            AppLog.probes.error("\(call.cli) could not start")
            throw CLILaunchError(cli: call.cli)
        }
        guard result.exitCode == 0 else {
            AppLog.probes.error("\(call.cli) exited with \(result.exitCode)")
            throw CLIExitError(cli: call.cli, exitCode: result.exitCode)
        }
        AppLog.probes.debug("\(call.cli) answered (\(result.output.count) chars)")
        return Response(text: result.output)
    }

    /// Plain pipes, with a PATH that finds the tools a login shell would.
    static let system: MakeExecutor = { environment in PipeCLIExecutor(environment: environment) }
}

/// `script` — the person's own script, run with `/bin/sh` from its folder,
/// its environment the definition's values and the secrets it names, read
/// from the login's vault. Answers with what it printed; a non-zero exit is
/// a fact, as for `command`.
struct ScriptFetcher: Fetching {
    let call: ScriptCall
    let providerId: String
    let secrets: (any SecretStore)?
    let makeExecutor: CommandFetcher.MakeExecutor

    func isReady() -> Bool {
        FileManager.default.fileExists(atPath: call.path)
    }

    func fetch(with credential: Credential?) async throws -> Response {
        // A setting the person never set and that has no default still reads
        // `{{setting.x}}`: it isn't passed, as extensions never passed one.
        var set = call.environment.filter { !$0.value.contains("{{setting.") }
        for (variable, setting) in call.secrets {
            if let value = secrets?.secret(setting, provider: providerId) { set[variable] = value }
        }
        let executor = makeExecutor(ProcessEnvironment(set: set))
        let name = (call.run as NSString).lastPathComponent
        guard isReady() else { throw CLIMissingError(cli: name) }
        let result: CLIResult
        do {
            result = try await executor.execute(
                binary: "/bin/sh", args: ["-c", call.path], input: nil, timeout: call.timeout,
                workingDirectory: URL(fileURLWithPath: call.folder, isDirectory: true), autoResponses: [:]
            )
        } catch let error as UsageError {
            throw error
        } catch {
            AppLog.probes.error("\(name) could not start")
            throw CLILaunchError(cli: name)
        }
        guard result.exitCode == 0 else {
            AppLog.probes.error("\(name) exited with \(result.exitCode)")
            throw CLIExitError(cli: name, exitCode: result.exitCode)
        }
        return Response(text: result.output)
    }
}

/// `cli` — drives a CLI in a terminal and answers with what the screen
/// showed, drawn by a terminal emulator first when the session asks for it.
struct CLIFetcher: Fetching {
    /// The executor for one session: its environment changes and ready markers.
    typealias MakeExecutor = @Sendable (CLICall) -> any CLIExecutor

    let call: CLICall
    let makeExecutor: MakeExecutor
    /// The session this worker runs in — one per worker, and the provider
    /// makes a worker per login, so each login keeps its own (#132).
    private let session = SessionMemory()

    func isReady() -> Bool {
        makeExecutor(call).locate(call.cli) != nil
    }

    func fetch(with credential: Credential?) async throws -> Response {
        let directory = call.workingDirectory?.url
        let result: CLIResult
        do {
            if let plan = call.session {
                result = try await CLISessionRunner(
                    call: call,
                    session: plan,
                    directory: directory,
                    makeExecutor: makeExecutor,
                    memory: session
                ).run()
            } else {
                result = try await makeExecutor(call).execute(
                    binary: call.cli,
                    args: call.args,
                    input: call.input,
                    timeout: call.timeout,
                    workingDirectory: directory,
                    autoResponses: call.autoResponses
                )
            }
        } catch UsageError.cliNotFound {
            // A fact, so the definition's `errors["cli.missing"]` words it.
            throw CLIMissingError(cli: call.cli)
        } catch let error as UsageError {
            throw error
        } catch {
            throw UsageError.executionFailed(error.localizedDescription)
        }
        AppLog.probes.debug("\(call.cli) screen captured (\(result.output.count) chars)")
        switch call.screen {
        case .raw: return Response(text: result.output)
        case .rendered: return Response(text: TerminalRenderer(cols: 160, rows: 50).render(result.output))
        }
    }

    /// The real terminal: `DefaultCLIExecutor` with the session's environment and ready markers.
    static let system: MakeExecutor = { call in
        DefaultCLIExecutor(
            environmentExclusions: call.environment.unset,
            environmentAdditions: call.environment.set,
            completionRule: call.readyWhen.isEmpty
                ? nil
                : CLICompletionRule(readyMarkers: call.readyWhen.map { CLICompletionRule.Marker($0.text, endsRow: $0.endsRow) }),
            inputDelay: call.inputDelay ?? 0.4
        )
    }
}

/// A command whose CLI isn't on this Mac — `errors["cli.missing"]`.
struct CLIMissingError: ReportedFailure {
    let cli: String
    var fact: ErrorFact? { .cliMissing }
    var reason: UsageError { .cliNotFound(cli) }
}

/// A command that exited non-zero — `errors["cli.nonzero"]`.
struct CLIExitError: ReportedFailure {
    let cli: String
    let exitCode: Int32
    var fact: ErrorFact? { .cliNonzero }
    var reason: UsageError { .executionFailed("`\(cli)` exited with code \(exitCode)") }
}

/// A command that could not be started — `errors["cli.failed"]`.
struct CLILaunchError: ReportedFailure {
    let cli: String
    var fact: ErrorFact? { .cliFailed }
    var reason: UsageError { .executionFailed("`\(cli)` could not be started") }
}

extension ProcessEnvironment {
    /// The environment with `{{token}}` and `{{setting.x}}` filled in. A value
    /// that names something unknown means the key is missing.
    func filled(with credential: Credential?) throws -> ProcessEnvironment {
        var values: [String: String] = [:]
        for (name, template) in set {
            guard let value = Template.fill(template, with: credential) else { throw UsageError.authenticationRequired }
            values[name] = value
        }
        return ProcessEnvironment(unset: unset, set: values)
    }
}

extension WorkingDirectory {
    /// Where the process starts.
    var url: URL? {
        switch self {
        case .dedicated: CLIWorkingDirectory.resolve()
        }
    }
}

/// `file` — reads a file some tool keeps up to date. Ready while it exists.
/// `directory` — the matching names in a folder, sorted.
struct DirectoryFetcher: Fetching {
    let call: DirectoryCall
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?

    private var path: String {
        Paths.resolve(call.path, homeDirectory: homeDirectory, environment: environment)
    }

    func isReady() -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
    }

    func fetch(with credential: Credential?) async throws -> Response {
        guard isReady(), let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            throw UsageError.executionFailed("No folder at \(call.path)")
        }
        let entries = names.filter { name in
            !name.hasPrefix(".") && (call.match.map { name.range(of: $0, options: .regularExpression) != nil } ?? true)
        }.sorted()
        return Response(body: try JSONSerialization.data(withJSONObject: ["entries": entries]))
    }
}

struct FileFetcher: Fetching {
    let call: FileCall
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?

    private var path: String {
        Paths.resolve(call.path, homeDirectory: homeDirectory, environment: environment)
    }

    func isReady() -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func fetch(with credential: Credential?) async throws -> Response {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw UsageError.executionFailed("No file at \(call.path)")
        }
        return Response(body: data)
    }
}
