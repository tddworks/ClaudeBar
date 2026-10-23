import Diagnostics
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The module's factory: the only place a case of `Fetch`, `Mapping` or
/// `CredentialLookup` meets the one connection it needs. Callers get a
/// `DataSource` and never name a worker.
public enum DataSources {
    /// Starts a CLI for a JSON-RPC conversation.
    public typealias TransportFactory = @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]?, _ workingDirectory: URL?) throws -> any RPCTransport

    /// The text of a mapping script, by the file name a definition gives.
    public typealias ScriptSource = @Sendable (_ file: String) -> String?

    /// A definition's path as the app sees it: platform app-data, `~` and
    /// `${VARIABLE:-default}` filled in by the same rule as file readers.
    public static func expandPath(
        _ path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> String {
        expandPath(path, platform: .current, homeDirectory: homeDirectory, environment: environment)
    }

    static func expandPath(_ path: String, platform: Platform, homeDirectory: URL,
                           environment: @escaping @Sendable (String) -> String?) -> String {
        Paths.expand(path, homeDirectory: homeDirectory,
                     environment: pathEnvironment(platform: platform, homeDirectory: homeDirectory, environment: environment))
    }

    /// Facts read only by path workers, separate from credential environment
    /// lookups. A process variable never overrides a reserved platform fact.
    static func pathEnvironment(platform: Platform, homeDirectory: URL,
                                environment: @escaping @Sendable (String) -> String?) -> @Sendable (String) -> String? {
        let appData = platform.applicationData?(homeDirectory, environment).path
        let separator = platform.pathSeparator
        return { name in
            switch name {
            case "platform.appData": appData
            case "platform.pathSeparator": separator
            default: environment(name)
            }
        }
    }

    /// Where this platform finds a CLI by name: its full path, or `nil` when
    /// it isn't installed or the platform can't look (§10).
    public static func locate(_ cli: String) -> String? {
        Platform.current.processes?.installed.find(cli)
    }

    /// The executor this platform runs a CLI in — its terminal and its program
    /// finder, what a `runCLI` fetch uses (§10). The app's own executors
    /// default to it; `additions` marks the sessions it starts (the probe key).
    public static func systemExecutor(_ additions: [String: String] = [:]) -> any CLIExecutor {
        guard let runCLI = Platform.current.runCLI else {
            preconditionFailure("\(Platform.current.name) has no terminal for a CLI to run in (§10)")
        }
        return runCLI(CLICall(cli: "system", environment: ProcessEnvironment(set: additions)))
    }

    /// A data source on this machine: the real network and this platform's
    /// connections.
    public static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        scripts: @escaping ScriptSource = { _ in nil },
        secrets: (any SecretStore)? = nil,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        loginShell: (@Sendable (String) -> String?)? = nil,
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil
    ) -> DataSource {
        make(
            definition,
            providerId: providerId,
            platform: .current,
            network: SameOriginRedirectClient.shared,
            cloudWatch: cloudWatch,
            priceCatalog: priceCatalog,
            scripts: scripts,
            secrets: secrets,
            loginShell: loginShell,
            environment: environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            now: { Date() }
        )
    }

    /// The same, with each connection handed in — how tests, here and in the
    /// modules above, run real definitions over stubbed connections. Every
    /// CLI and command runs on `cliExecutor`, whatever environment it asks
    /// for. A local server is found among `running` and asked through
    /// `network`, on every platform. This platform's screen renderer stays;
    /// a `nil` browser store means none.
    public static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        cliExecutor: any CLIExecutor,
        network: any NetworkClient,
        makeTransport: @escaping TransportFactory,
        security: @escaping @Sendable ([String]) -> (status: Int32, output: String) = { _ in (1, "") },
        scripts: @escaping ScriptSource = { _ in nil },
        secrets: (any SecretStore)? = nil,
        browserCookies: (any BrowserCookieReading)? = nil,
        browserStorage: (any BrowserStorageReading)? = nil,
        loginShell: (@Sendable (String) -> String?)? = nil,
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL,
        running: [RunningProgram] = [],
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil,
        now: @escaping @Sendable () -> Date
    ) -> DataSource {
        var platform = Platform.current
        platform.runCLI = { _ in cliExecutor }
        platform.processes = platform.processes?.with(pipes: { _ in cliExecutor }, conversation: makeTransport)
        platform.keychain = security
        platform.browserCookies = browserCookies
        platform.browserStorage = browserStorage
        platform.localServers = LocalServers(handing: running, network: network)
        return make(
            definition,
            providerId: providerId,
            platform: platform,
            network: network,
            cloudWatch: cloudWatch,
            priceCatalog: priceCatalog,
            scripts: scripts,
            secrets: secrets,
            loginShell: loginShell,
            environment: environment,
            homeDirectory: homeDirectory,
            now: now
        )
    }

    /// Each case meets the one connection it needs from `platform`, and a
    /// case whose connection is `nil` fails as `Unavailable` (§10).
    static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        platform: Platform,
        network: any NetworkClient,
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil,
        scripts: @escaping ScriptSource = { _ in nil },
        secrets: (any SecretStore)? = nil,
        loginShell: (@Sendable (String) -> String?)? = nil,
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date
    ) -> DataSource {
        let pathsEnvironment = pathEnvironment(platform: platform, homeDirectory: homeDirectory, environment: environment)
        let fetcher = fetcher(definition.fetch, providerId: providerId, platform: platform, network: network,
                              cloudWatch: cloudWatch, priceCatalog: priceCatalog, secrets: secrets,
                              environment: pathsEnvironment, homeDirectory: homeDirectory, now: now)

        let mapper: any Reading = switch definition.mapping {
        case .json(let mapping): JSONMapper(mapping: mapping, now: now)
        case .text(let mapping): TextMapper(mapping: mapping, now: now)
        case .script(let mapping): scriptMapper(mapping, source: scripts(mapping.file), platform: platform, now: now)
        case .usage: UsageMapper(now: now)
        }

        var refresher: (any CredentialRefreshing)?
        var lookup = definition.credential
        if case .refreshing(let base, let refresh)? = lookup {
            switch refresh {
            case .oauth2(let oauth):
                refresher = OAuth2Refresher(refresh: oauth, network: network, now: now)
            case .cli(let call):
                // No CLI on this platform: no renewal, as when a definition
                // declares none (§10). A refused token reads as refused.
                refresher = platform.runCLI.map {
                    CLIRefresher(call: call, executor: $0(call),
                                 directory: workingDirectory(call.workingDirectory, platform: platform,
                                                             homeDirectory: homeDirectory, environment: environment))
                }
            }
            lookup = base
        }

        let readers = Readers(environment: environment, pathEnvironment: pathsEnvironment, homeDirectory: homeDirectory,
                              secrets: secrets, providerId: providerId, platform: platform, loginShell: loginShell)
        return DataSource(
            definition: definition,
            providerId: providerId,
            credentials: lookup.map { readers.reader(for: $0) },
            refresher: refresher,
            fetcher: fetcher,
            mapper: mapper,
            contextFiles: definition.context.mapValues {
                JSONFileReader(file: $0, homeDirectory: homeDirectory, environment: pathsEnvironment)
            },
            recoveries: definition.recover.mapValues { recovery -> any Recovering in
                switch recovery {
                case .patchJSONFile(let path, let keys, let value):
                    JSONFilePatch(path: Paths.resolve(path, homeDirectory: homeDirectory, environment: pathsEnvironment), keys: keys, value: value, homeDirectory: homeDirectory, environment: pathsEnvironment,
                                  directory: { cliWorkingDirectory(platform: platform, homeDirectory: homeDirectory, environment: environment) })
                }
            },
            requiredFiles: definition.requiresFiles.map {
                Paths.expand($0, homeDirectory: homeDirectory, environment: pathsEnvironment)
            },
            now: now
        )
    }

    /// The worker for a fetch case. `cli`, `command`, `jsonRpc`, `script` and
    /// `localServer` run a program, so a platform that runs none fails them at
    /// fetching, naming what they would run, never as a program that isn't
    /// installed.
    private static func fetcher(
        _ fetch: Fetch,
        providerId: String,
        platform: Platform,
        network: any NetworkClient,
        cloudWatch: (any CloudWatchClient)?,
        priceCatalog: (any PriceCatalog)?,
        secrets: (any SecretStore)?,
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date
    ) -> any Fetching {
        func unavailable(_ what: String) -> any Fetching {
            Unavailable(.fetch, what, on: platform.name)
        }
        switch fetch {
        case .http(let request):
            return HTTPFetcher(request: request, network: network, zone: platform.timeZone, now: now)
        case .httpSteps(let steps):
            return HTTPStepsFetcher(steps: steps, network: network, zone: platform.timeZone, now: now)
        case .jsonRpc(let call):
            guard let processes = platform.processes else { return unavailable("Running \(call.cli)") }
            return JSONRPCFetcher(call: call, processes: processes,
                                  directory: workingDirectory(call.workingDirectory, platform: platform,
                                                              homeDirectory: homeDirectory, environment: environment))
        case .cli(let call):
            guard let runCLI = platform.runCLI else { return unavailable("Running \(call.cli)") }
            switch call.screen {
            case .raw:
                return CLIFetcher(call: call, makeExecutor: runCLI,
                                  directory: workingDirectory(call.workingDirectory, platform: platform,
                                                              homeDirectory: homeDirectory, environment: environment))
            case .rendered:
                guard let render = platform.screenRenderer else { return unavailable("Rendering \(call.cli)'s screen") }
                return CLIFetcher(call: call, makeExecutor: runCLI,
                                  directory: workingDirectory(call.workingDirectory, platform: platform,
                                                              homeDirectory: homeDirectory, environment: environment), screen: render)
            }
        case .command(let call):
            guard let processes = platform.processes else { return unavailable("Running \(call.cli)") }
            return CommandFetcher(call: call, processes: processes,
                                  directory: workingDirectory(call.workingDirectory, platform: platform,
                                                              homeDirectory: homeDirectory, environment: environment))
        case .file(let call):
            return FileFetcher(call: call, homeDirectory: homeDirectory, environment: environment)
        case .localServer(let call):
            guard let servers = platform.localServers else { return unavailable("Reading a local server") }
            return servers.fetcher(for: call)
        case .cloudWatch(let call):
            return CloudWatchFetcher(call: call, client: cloudWatch, catalog: priceCatalog, zone: platform.timeZone, now: now)
        case .directory(let call):
            return DirectoryFetcher(call: call, homeDirectory: homeDirectory, environment: environment)
        case .sqlite(let call):
            return SQLiteFetcher(call: call, homeDirectory: homeDirectory, environment: environment)
        case .script(let call):
            guard let processes = platform.processes else { return unavailable("Running a script") }
            return ScriptFetcher(call: call, providerId: providerId, secrets: secrets, processes: processes,
                                 directory: URL(fileURLWithPath: Paths.expand(call.folder, homeDirectory: homeDirectory, environment: environment),
                                                isDirectory: true))
        }
    }

    /// Resolve the trusted directory only when the CLI actually starts, as
    /// before; a source that hasn't been checked creates nothing on disk.
    private static func workingDirectory(_ directory: WorkingDirectory?, platform: Platform, homeDirectory: URL,
                                         environment: @escaping @Sendable (String) -> String?) -> @Sendable () -> URL? {
        { directory.map { _ in cliWorkingDirectory(platform: platform, homeDirectory: homeDirectory, environment: environment) } }
    }

    /// A `script` mapping runs on QuickJS, the one engine (#570).
    private static func scriptMapper(_ mapping: ScriptMapping, source: String?, platform: Platform,
                                     now: @escaping @Sendable () -> Date) -> any Reading {
        ScriptMapper(file: mapping.file, source: source, values: mapping.values, engine: QuickJSEngine(),
                     zone: platform.timeZone, now: now)
    }

    private struct Readers {
        let environment: @Sendable (String) -> String?
        let pathEnvironment: @Sendable (String) -> String?
        let homeDirectory: URL
        let secrets: (any SecretStore)?
        let providerId: String
        let platform: Platform
        let loginShell: (@Sendable (String) -> String?)?

        func reader(for lookup: CredentialLookup) -> any CredentialFinding {
            switch lookup {
            case .environment(let name, let asksShell):
                return EnvironmentReader(name: name, environment: environment, loginShell: asksShell ? loginShell : nil)
            case .jsonFile(let file):
                return JSONFileReader(file: file, homeDirectory: homeDirectory, environment: pathEnvironment)
            case .keychain(let item):
                guard let keychain = platform.keychain else { return unavailable("Reading a Keychain item") }
                return KeychainReader(item: item, security: keychain)
            case .setting(let name):
                return SettingReader(name: name, providerId: providerId, secrets: secrets)
            case .refined(let base, let refinement):
                return RefinedReader(base: reader(for: base), refinement: refinement)
            case .sqlite(let database):
                return SQLiteReader(file: database, homeDirectory: homeDirectory, environment: pathEnvironment)
            case .browserCookies(let query):
                guard let cookies = platform.browserCookies else { return unavailable("Reading a browser's cookies") }
                return BrowserCookieReader(query: query, cookies: cookies)
            case .browserStorage(let query):
                guard let storage = platform.browserStorage else { return unavailable("Reading a browser's storage") }
                return BrowserStorageReader(query: query, storage: storage)
            case .firstOf(let lookups):
                return FirstOfReader(readers: lookups.map { reader(for: $0) })
            case .refreshing(let base, _):
                // A refresh nested inside `firstOf` is refreshed by the outer
                // data source only; reading still works.
                return reader(for: base)
            }
        }

        private func unavailable(_ what: String) -> any CredentialFinding {
            Unavailable(.lookup, what, on: platform.name)
        }
    }
}

/// `recover.patchJSONFile` — sets one value deep in a JSON file that already
/// exists, e.g. a CLI's "I trust this folder" flag. `true` only when it changed
/// the file, so a second failure is not retried forever.
struct JSONFilePatch: Recovering {
    let path: String
    let keys: [String]
    let value: JSONValue
    let homeDirectory: URL
    let environment: @Sendable (String) -> String?
    let directory: @Sendable () -> URL

    func recover() -> Bool {
        let url = URL(fileURLWithPath: Paths.expand(path, homeDirectory: homeDirectory, environment: environment))
        guard let data = try? Data(contentsOf: url),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        let cliDirectory = directory().path
        let keys = keys.map { $0.replacingOccurrences(of: "{{cliDirectory}}", with: cliDirectory) }
        guard let patched = Self.set(value.foundationObject, at: keys[...], in: document) else { return false }
        do {
            let output = try JSONSerialization.data(withJSONObject: patched, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: url, options: .atomic)
            AppLog.probes.info("Patched \(path) so the CLI can run in the probe directory")
            return true
        } catch {
            AppLog.probes.error("Could not patch \(path): \(error.localizedDescription)")
            return false
        }
    }

    /// The document with the value set, or `nil` when it already had it or a
    /// key on the way is not an object.
    private static func set(_ value: Any, at keys: ArraySlice<String>, in object: [String: Any]) -> [String: Any]? {
        guard let key = keys.first else { return nil }
        var copy = object
        if keys.count == 1 {
            if let existing = object[key] as? NSObject, let new = value as? NSObject, existing.isEqual(new) { return nil }
            copy[key] = value
            return copy
        }
        let child: [String: Any]
        switch object[key] {
        case nil: child = [:]
        case let existing as [String: Any]: child = existing
        default: return nil
        }
        guard let updated = set(value, at: keys.dropFirst(), in: child) else { return nil }
        copy[key] = updated
        return copy
    }
}
