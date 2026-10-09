import Foundation
import Mockable

/// HOW TO GET THE BYTES — *Data fetching method*. A closed sum, one case per
/// JSON tag, because the decoder must know every tag and the picker is a fixed
/// list. A new protocol is a new case and one new worker.
public enum Fetch: Sendable, Equatable {
    /// An HTTP request — the *API* choice.
    case http(HTTPRequest)
    /// HTTP requests in order, each able to use what an earlier one said —
    /// also the *API* choice, written `"http": { "steps": […] }`.
    case httpSteps(HTTPSteps)
    /// A JSON-RPC conversation with a CLI over stdin/stdout.
    case jsonRpc(JSONRPCCall)
    /// A CLI run in a terminal, its screen captured — for a TUI.
    case cli(CLICall)
    /// A command run over pipes, its output and exit code read.
    case command(CommandCall)
    /// A file on this Mac that some tool keeps up to date — the *File* choice.
    case file(FileCall)
    /// An app's own server on this Mac, found through its running process.
    case localServer(LocalServerCall)
    /// A cloud's metrics, summed per dimension value — through `CloudWatchClient`.
    case cloudWatch(CloudWatchCall)
    /// A folder some tool fills — the names in it.
    case directory(DirectoryCall)
    /// `"sqlite": { "path": "~/…/state.vscdb", "query": "SELECT …" }` — rows
    /// of an app's own database, read-only.
    case sqlite(SQLiteCall)
    /// A script of the person's, run from its own folder with every setting
    /// in its environment — what an extension's section runs.
    case script(ScriptCall)
}

/// `"script": { "run": "./probe.sh", "folder": "/Users/you/.claudebar/extensions/acme",
/// "environment": { "CLAUDEBAR_REGION": "{{setting.region}}" },
/// "secrets": { "CLAUDEBAR_API_KEY": "apiKey" }, "timeout": 10 }` — runs `run`
/// with `/bin/sh` from `folder`. `environment` is filled like any definition
/// string; each of `secrets` is a setting read from the login's vault, so a
/// script may take several keys (a `command` reaches one, as `{{token}}`).
public struct ScriptCall: Sendable, Equatable, Codable {
    public let run: String
    public let folder: String
    public let environment: [String: String]
    /// Environment variable → the vault setting whose value it takes.
    public let secrets: [String: String]
    public let timeout: TimeInterval

    public init(run: String, folder: String, environment: [String: String] = [:], secrets: [String: String] = [:], timeout: TimeInterval = 10) {
        self.run = run
        self.folder = folder
        self.environment = environment
        self.secrets = secrets
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            run: try container.decode(String.self, forKey: .run),
            folder: try container.decode(String.self, forKey: .folder),
            environment: try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:],
            secrets: try container.decodeIfPresent([String: String].self, forKey: .secrets) ?? [:],
            timeout: try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 10
        )
    }

    /// The script's own path: `run` in `folder`, unless it is absolute.
    var path: String {
        if run.hasPrefix("/") { return run }
        let relative = run.hasPrefix("./") ? String(run.dropFirst(2)) : run
        return URL(fileURLWithPath: folder).appendingPathComponent(relative).path
    }

    private enum CodingKeys: String, CodingKey { case run, folder, environment, secrets, timeout }
}

/// `"directory": { "path": "~/.tool/logs", "match": "^session_" }` — the
/// names of the entries in a folder, sorted; ready while the folder exists.
public struct DirectoryCall: Sendable, Equatable, Codable {
    public let path: PathPattern
    /// A pattern an entry's name must match; every entry when absent.
    public let match: String?

    public init(path: PathPattern, match: String? = nil) {
        self.path = path
        self.match = match
    }
}

/// `"sqlite": { "path": "~/…/state.vscdb", "query": "SELECT value FROM …" }`
/// — the rows an app's own database answers, each column as text. Opened
/// read-only; a query that would change it is refused.
public struct SQLiteCall: Sendable, Equatable, Codable {
    public let path: PathPattern
    public let query: String

    public init(path: PathPattern, query: String) {
        self.path = path
        self.query = query
    }
}

/// `"cloudWatch": {…}` — today's sums of `metrics` in `namespace`, one row per
/// `dimension` value in each region, read with the person's own cloud
/// profile. With `prices`, each row's unit prices come with it from the
/// `PriceCatalog`, so a mapping can turn usage into money.
public struct CloudWatchCall: Sendable, Equatable, Codable {
    public let namespace: String
    public let dimension: String
    public let metrics: [String]
    /// Comma-separated — `"{{setting.regions}}"`.
    public let regions: String
    /// A named profile, or blank for the default credentials.
    public let profile: String?
    /// The service whose price list prices each dimension value.
    public let prices: String?

    public init(namespace: String, dimension: String, metrics: [String], regions: String, profile: String? = nil, prices: String? = nil) {
        self.namespace = namespace
        self.dimension = dimension
        self.metrics = metrics
        self.regions = regions
        self.profile = profile
        self.prices = prices
    }

    /// The regions named, without blanks or a template left unfilled.
    var regionList: [String] {
        regions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.contains("{{") }
    }

    /// The profile, unless it was left blank.
    var profileName: String? {
        guard let profile = profile?.trimmingCharacters(in: .whitespaces), !profile.isEmpty, !profile.contains("{{") else { return nil }
        return profile
    }
}

/// A cloud's metrics service. Implemented where its SDK is linked.
@Mockable
public protocol CloudWatchClient: Sendable {
    /// Each `dimension` value's sum of each metric between `from` and `to`.
    func sums(namespace: String, dimension: String, metrics: [String], region: String, profile: String?,
              from: Date, to: Date) async throws -> [String: [String: Double]]
}

/// A cloud's price list: what each thing costs, as exact decimal texts by
/// field — `{"input": "3", "output": "15", "per": "1000000", "name": "…"}`.
@Mockable
public protocol PriceCatalog: Sendable {
    func prices(service: String, ids: [String]) async -> [String: [String: String]]
}

/// `"localServer": {…}` — an app that serves its usage on 127.0.0.1: its
/// process is found by name (`pgrep`), the values it was started with read
/// from its command line, its listening ports looked up (`lsof`), and the
/// declared paths asked on each port in turn. Self-signed TLS is accepted on
/// the loopback address only.
public struct LocalServerCall: Sendable, Equatable, Codable {
    /// Which process: its name contains one of `names`, and its command line
    /// matches one of `match` (any, when empty).
    public struct Process: Sendable, Equatable, Codable {
        public let names: [String]
        public let match: [String]

        public init(names: [String], match: [String] = []) {
            self.names = names
            self.match = match
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            names = try container.decode([String].self, forKey: .names)
            match = try container.decodeIfPresent([String].self, forKey: .match) ?? []
        }
    }

    /// What `cli.missing` names when no such process runs — "Antigravity".
    public let app: String
    public let process: Process
    /// Name → a pattern over the command line; its first group is the value,
    /// filled as `{{name}}`.
    public let values: [String: String]
    /// Values the server can't be asked without: missing is *Key needed*.
    public let required: [String]
    /// Asked in order on every listening port; the first 200 answers.
    public let paths: [String]
    /// A value holding a port also asked over plain HTTP, last.
    public let plainHTTPPort: String?
    public let method: String
    public let headers: [String: String]
    public let body: String?
    public let timeout: TimeInterval

    public init(app: String, process: Process, values: [String: String] = [:], required: [String] = [], paths: [String],
                plainHTTPPort: String? = nil, method: String = "POST", headers: [String: String] = [:], body: String? = nil,
                timeout: TimeInterval = 8) {
        self.app = app
        self.process = process
        self.values = values
        self.required = required
        self.paths = paths
        self.plainHTTPPort = plainHTTPPort
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decode(String.self, forKey: .app)
        process = try container.decode(Process.self, forKey: .process)
        values = try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:]
        required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
        paths = try container.decode([String].self, forKey: .paths)
        plainHTTPPort = try container.decodeIfPresent(String.self, forKey: .plainHTTPPort)
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "POST"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try container.decodeIfPresent(String.self, forKey: .body)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 8
    }
}

/// `{ "path": "~/.tool/usage.json" }` — `~` and `${VAR:-default}` expand; a
/// `*` or a list of paths reads the most recently changed file.
public struct FileCall: Sendable, Equatable, Codable {
    public let path: PathPattern

    public init(path: PathPattern) {
        self.path = path
    }
}

/// `{{name}}` placeholders in `url`, `headers` and `body` are filled from the
/// credential at fetch time.
public struct HTTPRequest: Sendable, Equatable, Codable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let body: String?
    public let timeout: TimeInterval
    /// The statuses that are an answer — part of the protocol, not of how a
    /// failure is worded. `nil`: 2xx.
    public let acceptedStatuses: [Int]?

    public init(url: String, method: String = "GET", headers: [String: String] = [:], body: String? = nil,
                timeout: TimeInterval = 15, acceptedStatuses: [Int]? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.acceptedStatuses = acceptedStatuses
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "GET"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        body = try container.decodeIfPresent(String.self, forKey: .body)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 15
        acceptedStatuses = try container.decodeIfPresent([Int].self, forKey: .acceptedStatuses)
    }

    /// Whether a status is an answer rather than a failure.
    public func accepts(_ status: Int) -> Bool {
        acceptedStatuses?.contains(status) ?? (200..<300).contains(status)
    }
}

/// `"http": { "steps": […] }` — call A, then B with something A said. The
/// response is every step's answer by name — `{ "whoami": …, "credits": … }`
/// — so the mapping and *Test Connection* see them all; at most eight steps.
public struct HTTPSteps: Sendable, Equatable, Codable {
    public static let limit = 8

    public let steps: [HTTPStep]

    public init(steps: [HTTPStep]) {
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode([HTTPStep].self, forKey: .steps)
        guard !steps.isEmpty, steps.count <= Self.limit else {
            throw DecodingError.dataCorruptedError(forKey: .steps, in: container,
                debugDescription: "http.steps needs 1 to \(Self.limit) steps")
        }
        guard Set(steps.map(\.name)).count == steps.count else {
            throw DecodingError.dataCorruptedError(forKey: .steps, in: container,
                debugDescription: "http.steps names must be unique")
        }
    }
}

/// One request in `http.steps`.
public struct HTTPStep: Sendable, Equatable, Codable {
    /// A value read from a step's response, for later steps' `{{name}}`.
    public enum Keep: Sendable, Equatable, Codable {
        /// `"$.path"` in a JSON body, or a list of them — the first that answers.
        case paths([String])
        /// `{ "pattern": "…" }` over the body's text; the first group.
        case pattern(String)

        private enum Keys: String, CodingKey { case pattern }

        public init(from decoder: Decoder) throws {
            if let path = try? decoder.singleValueContainer().decode(String.self) {
                self = .paths([path])
            } else if let paths = try? decoder.singleValueContainer().decode([String].self) {
                self = .paths(paths)
            } else {
                self = .pattern(try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .pattern))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .paths(let paths):
                var container = encoder.singleValueContainer()
                if paths.count == 1 { try container.encode(paths[0]) } else { try container.encode(paths) }
            case .pattern(let pattern):
                var container = encoder.container(keyedBy: Keys.self)
                try container.encode(pattern, forKey: .pattern)
            }
        }
    }

    public let name: String
    public let request: HTTPRequest
    public let keep: [String: Keep]
    /// A failure leaves this step's values unknown instead of ending the fetch.
    public let optional: Bool
    /// Skipped when this value is already known.
    public let unless: String?
    /// Tries again on a network failure or a 5xx, up to this many times in all.
    public let attempts: Int
    /// Values that may be missing: a JSON body key, a URL query item or a
    /// header filled with one is left out when it came out empty, instead of
    /// failing.
    public let dropEmpty: [String]

    public init(name: String, request: HTTPRequest, keep: [String: Keep] = [:], optional: Bool = false,
                unless: String? = nil, attempts: Int = 1, dropEmpty: [String] = []) {
        self.name = name
        self.request = request
        self.keep = keep
        self.optional = optional
        self.unless = unless
        self.attempts = attempts
        self.dropEmpty = dropEmpty
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        request = try container.decode(HTTPRequest.self, forKey: .request)
        keep = try container.decodeIfPresent([String: Keep].self, forKey: .keep) ?? [:]
        optional = try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false
        unless = try container.decodeIfPresent(String.self, forKey: .unless)
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 1
        dropEmpty = try container.decodeIfPresent([String].self, forKey: .dropEmpty) ?? []
        guard (1...3).contains(attempts) else {
            throw DecodingError.dataCorruptedError(forKey: .attempts, in: container,
                debugDescription: "a step's attempts is 1 to 3")
        }
    }
}

/// `"command": { "cli": "tool", "args": ["usage", "--json"] }` — runs a
/// command over pipes and reads what it printed. Its exit code is reported,
/// never ignored. A TUI that only draws in a terminal is a `cli` instead.
public struct CommandCall: Sendable, Equatable, Codable {
    public typealias Environment = ProcessEnvironment

    public let cli: String
    public let args: [String]
    /// Text written to the command's standard input — `"/usage\n/quit\n"`.
    public let input: String?
    public let timeout: TimeInterval
    public let workingDirectory: WorkingDirectory?
    public let environment: ProcessEnvironment

    public init(cli: String, args: [String] = [], input: String? = nil, timeout: TimeInterval = 20,
                workingDirectory: WorkingDirectory? = nil, environment: ProcessEnvironment = ProcessEnvironment()) {
        self.cli = cli
        self.args = args
        self.input = input
        self.timeout = timeout
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cli = try container.decode(String.self, forKey: .cli)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        input = try container.decodeIfPresent(String.self, forKey: .input)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 20
        workingDirectory = try container.decodeIfPresent(WorkingDirectory.self, forKey: .workingDirectory)
        environment = try container.decodeIfPresent(ProcessEnvironment.self, forKey: .environment) ?? ProcessEnvironment()
    }
}

/// Where a CLI runs. `dedicated` is ClaudeBar's own trusted directory, so a
/// CLI's folder-trust prompt never blocks a fetch.
public enum WorkingDirectory: String, Sendable, Equatable, Codable {
    /// ClaudeBar's own folder, so a CLI's folder-trust prompt never blocks it.
    case dedicated
}

/// Starts `cli args…`, sends the `handshake` in order, then `call`, and answers
/// with the call's result.
public struct JSONRPCCall: Sendable, Equatable, Codable {
    public struct Step: Sendable, Equatable, Codable {
        /// A request, answered before the next step.
        public let request: String?
        /// A notification, never answered.
        public let notify: String?
        public let params: JSONValue?

        public init(request: String? = nil, notify: String? = nil, params: JSONValue? = nil) {
            self.request = request
            self.notify = notify
            self.params = params
        }
    }

    /// A request after the call, its whole answer added to the response
    /// under `as` — e.g. the account behind the usage.
    public struct FollowUp: Sendable, Equatable, Codable {
        public let request: String
        public let params: JSONValue?
        public let `as`: String

        public init(request: String, params: JSONValue? = nil, as name: String) {
            self.request = request
            self.params = params
            self.as = name
        }
    }

    public let cli: String
    public let args: [String]
    public let workingDirectory: WorkingDirectory?
    public let handshake: [Step]
    public let call: String
    public let params: JSONValue?
    public let then: [FollowUp]
    /// Variables to remove from, and add to, the CLI's environment.
    public let environment: ProcessEnvironment
    /// Seconds the whole exchange may take before the CLI is stopped and the
    /// fetch fails with a timeout — a CLI that stalls never answers (#517).
    public let timeout: TimeInterval
    /// What an error answer's message means — e.g. "authentication required"
    /// is a signed-out CLI (#525). Any other error answer is an execution failure.
    public let errors: [TextMapping.ErrorRule]

    public init(
        cli: String,
        args: [String],
        workingDirectory: WorkingDirectory? = nil,
        handshake: [Step] = [],
        call: String,
        params: JSONValue? = nil,
        then: [FollowUp] = [],
        environment: ProcessEnvironment = ProcessEnvironment(),
        timeout: TimeInterval = 15,
        errors: [TextMapping.ErrorRule] = []
    ) {
        self.cli = cli
        self.args = args
        self.workingDirectory = workingDirectory
        self.handshake = handshake
        self.call = call
        self.params = params
        self.then = then
        self.environment = environment
        self.timeout = timeout
        self.errors = errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cli = try container.decode(String.self, forKey: .cli)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        workingDirectory = try container.decodeIfPresent(WorkingDirectory.self, forKey: .workingDirectory)
        handshake = try container.decodeIfPresent([Step].self, forKey: .handshake) ?? []
        call = try container.decode(String.self, forKey: .call)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
        then = try container.decodeIfPresent([FollowUp].self, forKey: .then) ?? []
        environment = try container.decodeIfPresent(ProcessEnvironment.self, forKey: .environment) ?? ProcessEnvironment()
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 15
        errors = try container.decodeIfPresent([TextMapping.ErrorRule].self, forKey: .errors) ?? []
    }
}

/// Variables to remove from, and add to, a CLI's environment. Each process
/// gets its own; the app's is never changed. `{{token}}` in a value is filled
/// when a `command` starts.
public struct ProcessEnvironment: Sendable, Equatable, Codable {
    public let unset: [String]
    public let set: [String: String]

    public init(unset: [String] = [], set: [String: String] = [:]) {
        self.unset = unset
        self.set = set
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unset = try container.decodeIfPresent([String].self, forKey: .unset) ?? []
        set = try container.decodeIfPresent([String: String].self, forKey: .set) ?? [:]
    }
}

/// Runs `cli args…` in a terminal, types `input`, answers prompts it
/// recognises from `autoResponses`, and returns what the screen showed.
public struct CLICall: Sendable, Equatable, Codable {
    public typealias Environment = ProcessEnvironment

    /// Text that means the screen has finished drawing: a phrase, or
    /// `{ "row": "…" }` for a phrase that must end its row.
    public struct ReadyMarker: Sendable, Equatable, Codable {
        public let text: String
        public let endsRow: Bool

        public init(_ text: String, endsRow: Bool = false) {
            self.text = text
            self.endsRow = endsRow
        }

        private enum Keys: String, CodingKey { case row }

        public init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                self.init(text)
                return
            }
            let container = try decoder.container(keyedBy: Keys.self)
            self.init(try container.decode(String.self, forKey: .row), endsRow: true)
        }

        public func encode(to encoder: Encoder) throws {
            if endsRow {
                var container = encoder.container(keyedBy: Keys.self)
                try container.encode(text, forKey: .row)
            } else {
                var container = encoder.singleValueContainer()
                try container.encode(text)
            }
        }
    }

    /// How the captured output reaches the mapping.
    public enum Screen: String, Sendable, Equatable, Codable {
        /// The raw bytes, escape codes and all.
        case raw
        /// Drawn by a terminal emulator first, so a TUI's cursor moves land
        /// where they put the text.
        case rendered
    }

    public let cli: String
    public let args: [String]
    public let input: String?
    public let timeout: TimeInterval
    public let workingDirectory: WorkingDirectory?
    /// Prompt text → what to type when it appears.
    public let autoResponses: [String: String]
    public let environment: Environment
    public let readyWhen: [ReadyMarker]
    public let screen: Screen
    /// Run in one session instead of a fresh one per run (#132).
    public let session: Session?
    /// Seconds to let a TUI finish its startup paint before `input` is typed;
    /// typed sooner, a redraw can discard it. Unset is the terminal's default.
    public let inputDelay: TimeInterval?

    public init(
        cli: String,
        args: [String] = [],
        input: String? = nil,
        timeout: TimeInterval = 20,
        workingDirectory: WorkingDirectory? = nil,
        autoResponses: [String: String] = [:],
        environment: Environment = Environment(),
        readyWhen: [ReadyMarker] = [],
        screen: Screen = .raw,
        session: Session? = nil,
        inputDelay: TimeInterval? = nil
    ) {
        self.cli = cli
        self.args = args
        self.input = input
        self.timeout = timeout
        self.workingDirectory = workingDirectory
        self.autoResponses = autoResponses
        self.environment = environment
        self.readyWhen = readyWhen
        self.screen = screen
        self.session = session
        self.inputDelay = inputDelay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cli = try container.decode(String.self, forKey: .cli)
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        input = try container.decodeIfPresent(String.self, forKey: .input)
        timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? 20
        workingDirectory = try container.decodeIfPresent(WorkingDirectory.self, forKey: .workingDirectory)
        inputDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .inputDelay)
        autoResponses = try container.decodeIfPresent([String: String].self, forKey: .autoResponses) ?? [:]
        environment = try container.decodeIfPresent(Environment.self, forKey: .environment) ?? Environment()
        readyWhen = try container.decodeIfPresent([ReadyMarker].self, forKey: .readyWhen) ?? []
        screen = try container.decodeIfPresent(Screen.self, forKey: .screen) ?? .raw
        session = try container.decodeIfPresent(Session.self, forKey: .session)
    }

    private enum CodingKeys: String, CodingKey {
        case cli, args, input, timeout, workingDirectory, autoResponses, environment, readyWhen, screen, session, inputDelay
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cli, forKey: .cli)
        try container.encode(args, forKey: .args)
        try container.encodeIfPresent(input, forKey: .input)
        try container.encode(timeout, forKey: .timeout)
        try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try container.encode(autoResponses, forKey: .autoResponses)
        try container.encode(environment, forKey: .environment)
        try container.encode(readyWhen, forKey: .readyWhen)
        try container.encode(screen, forKey: .screen)
        try container.encodeIfPresent(session, forKey: .session)
        try container.encodeIfPresent(inputDelay, forKey: .inputDelay)
    }
}

extension CLICall {
    /// The one session every run of a call shares (#132) — a poll that starts
    /// the CLI again and again keeps **one** session instead of leaving a
    /// fresh, empty one behind per run.
    ///
    /// Only the vendor's facts are data: the args that create the session and
    /// the args that resume it (`{{id}}` is the id), the output that says the
    /// session is gone, and the output — trusted only on a non-zero exit —
    /// that says this CLI build refuses the flags, so every later run falls
    /// back to the call's plain args. Which session a login is in is the
    /// worker's own memory, never part of a definition.
    public struct Session: Sendable, Equatable, Codable {
        /// How the session's id is chosen. Without one, a random id the worker
        /// remembers for its lifetime.
        public enum ID: Sendable, Equatable, Codable {
            /// `{ "stable": "ClaudeBar Probe" }` — a UUID derived from this text
            /// and the call's environment: one per login, the same forever.
            case stable(String)

            private enum CodingKeys: String, CodingKey { case stable }

            public init(from decoder: Decoder) throws {
                self = .stable(try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .stable))
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .stable(let text): try container.encode(text, forKey: .stable)
                }
            }
        }

        public let id: ID?
        /// Args appended to the call that creates the session.
        public let create: [String]
        /// Args appended to a run that resumes the session.
        public let resume: [String]
        /// Output meaning a stable session's id is already taken — the same id
        /// is resumed.
        public let resumeOn: [String]
        /// Output meaning the session no longer exists — it is created again
        /// under a fresh id.
        public let recreateOn: [String]
        /// Output meaning the CLI rejected the session flags. Only honoured
        /// when the run also exited non-zero: the words alone can come from a
        /// prompt or a hook's transcript.
        public let unsupportedOn: [String]

        public init(id: ID? = nil, create: [String], resume: [String], resumeOn: [String] = [],
                    recreateOn: [String] = [], unsupportedOn: [String] = []) {
            self.id = id
            self.create = create
            self.resume = resume
            self.resumeOn = resumeOn
            self.recreateOn = recreateOn
            self.unsupportedOn = unsupportedOn
        }

        private enum CodingKeys: String, CodingKey { case id, create, resume, resumeOn, recreateOn, unsupportedOn }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(ID.self, forKey: .id)
            create = try container.decode([String].self, forKey: .create)
            resume = try container.decode([String].self, forKey: .resume)
            resumeOn = try container.decodeIfPresent([String].self, forKey: .resumeOn) ?? []
            recreateOn = try container.decodeIfPresent([String].self, forKey: .recreateOn) ?? []
            unsupportedOn = try container.decodeIfPresent([String].self, forKey: .unsupportedOn) ?? []
        }
    }
}

// MARK: - JSON

extension Fetch: Codable {
    private static let tags = ["http", "jsonRpc", "cli", "command", "file", "localServer", "cloudWatch", "directory", "sqlite", "script"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TagKey.self)
        switch try container.singleTag(of: Self.tags, in: "fetch") {
        case "http":
            let http = try container.nestedContainer(keyedBy: TagKey.self, forKey: TagKey("http"))
            self = http.contains(TagKey("steps"))
                ? .httpSteps(try container.decode(HTTPSteps.self, forKey: TagKey("http")))
                : .http(try container.decode(HTTPRequest.self, forKey: TagKey("http")))
        case "jsonRpc": self = .jsonRpc(try container.decode(JSONRPCCall.self, forKey: TagKey("jsonRpc")))
        case "file": self = .file(try container.decode(FileCall.self, forKey: TagKey("file")))
        case "command": self = .command(try container.decode(CommandCall.self, forKey: TagKey("command")))
        case "localServer": self = .localServer(try container.decode(LocalServerCall.self, forKey: TagKey("localServer")))
        case "cloudWatch": self = .cloudWatch(try container.decode(CloudWatchCall.self, forKey: TagKey("cloudWatch")))
        case "directory": self = .directory(try container.decode(DirectoryCall.self, forKey: TagKey("directory")))
        case "sqlite": self = .sqlite(try container.decode(SQLiteCall.self, forKey: TagKey("sqlite")))
        case "script": self = .script(try container.decode(ScriptCall.self, forKey: TagKey("script")))
        default: self = .cli(try container.decode(CLICall.self, forKey: TagKey("cli")))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TagKey.self)
        switch self {
        case .http(let request): try container.encode(request, forKey: TagKey("http"))
        case .httpSteps(let steps): try container.encode(steps, forKey: TagKey("http"))
        case .jsonRpc(let call): try container.encode(call, forKey: TagKey("jsonRpc"))
        case .cli(let call): try container.encode(call, forKey: TagKey("cli"))
        case .command(let call): try container.encode(call, forKey: TagKey("command"))
        case .file(let call): try container.encode(call, forKey: TagKey("file"))
        case .localServer(let call): try container.encode(call, forKey: TagKey("localServer"))
        case .cloudWatch(let call): try container.encode(call, forKey: TagKey("cloudWatch"))
        case .directory(let call): try container.encode(call, forKey: TagKey("directory"))
        case .sqlite(let call): try container.encode(call, forKey: TagKey("sqlite"))
        case .script(let call): try container.encode(call, forKey: TagKey("script"))
        }
    }
}
