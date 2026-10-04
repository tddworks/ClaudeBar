import Diagnostics
import Foundation

/// The module's factory: the only place a case of `Fetch`, `Mapping` or
/// `CredentialLookup` meets the one connection it needs. Callers get a
/// `DataSource` and never name a worker.
public enum DataSources {
    /// Starts a CLI for a JSON-RPC conversation.
    public typealias TransportFactory = @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]?, _ workingDirectory: URL?) throws -> any RPCTransport

    /// The text of a mapping script, by the file name a definition gives.
    public typealias ScriptSource = @Sendable (_ file: String) -> String?

    /// A definition's path as the app sees it: `~` and `${VARIABLE:-default}` filled in.
    public static func expandPath(
        _ path: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] }
    ) -> String {
        Paths.expand(path, homeDirectory: homeDirectory, environment: environment)
    }

    /// A data source on the real network, CLI, Keychain and file system.
    public static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        scripts: @escaping ScriptSource = { _ in nil },
        secrets: (any SecretStore)? = nil,
        environment: @escaping @Sendable (String) -> String? = { ProcessInfo.processInfo.environment[$0] },
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil
    ) -> DataSource {
        make(
            definition,
            providerId: providerId,
            makeCLIExecutor: CLIFetcher.system,
            makeCommandExecutor: CommandFetcher.system,
            network: URLSession.shared,
            cloudWatch: cloudWatch,
            priceCatalog: priceCatalog,
            makeTransport: { executable, arguments, environment, directory in
                try ProcessRPCTransport(executable: executable, arguments: arguments, environment: environment, workingDirectory: directory)
            },
            security: KeychainReader.system,
            scripts: scripts,
            secrets: secrets,
            browserCookies: SystemBrowserCookies(),
            environment: environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            now: { Date() }
        )
    }

    /// The same, with each connection handed in — how tests, here and in the
    /// modules above, run real definitions over stubbed connections. Every
    /// CLI and command runs on `cliExecutor`, whatever environment it asks for.
    public static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        cliExecutor: any CLIExecutor,
        network: any NetworkClient,
        makeTransport: @escaping TransportFactory,
        security: @escaping @Sendable ([String]) -> (status: Int32, output: String) = { _ in (1, "") },
        scripts: @escaping ScriptSource = { _ in nil },
        secrets: (any SecretStore)? = nil,
        browserCookies: any BrowserCookieReading = SystemBrowserCookies(),
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL,
        processPaths: @escaping @Sendable () -> [String] = { [] },
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil,
        now: @escaping @Sendable () -> Date
    ) -> DataSource {
        make(
            definition,
            providerId: providerId,
            makeCLIExecutor: { _ in cliExecutor },
            makeCommandExecutor: { _ in cliExecutor },
            network: network,
            localNetwork: network,
            processPaths: processPaths,
            cloudWatch: cloudWatch,
            priceCatalog: priceCatalog,
            makeTransport: makeTransport,
            security: security,
            scripts: scripts,
            secrets: secrets,
            browserCookies: browserCookies,
            environment: environment,
            homeDirectory: homeDirectory,
            now: now
        )
    }

    static func make(
        _ definition: DataSourceDefinition,
        providerId: String,
        makeCLIExecutor: @escaping CLIFetcher.MakeExecutor,
        makeCommandExecutor: @escaping CommandFetcher.MakeExecutor,
        network: any NetworkClient,
        localNetwork: any NetworkClient = InsecureLocalhostNetworkClient(),
        processPaths: @escaping @Sendable () -> [String] = RunningProcesses.system,
        cloudWatch: (any CloudWatchClient)? = nil,
        priceCatalog: (any PriceCatalog)? = nil,
        makeTransport: @escaping TransportFactory,
        security: @escaping KeychainReader.Security,
        scripts: @escaping ScriptSource,
        secrets: (any SecretStore)?,
        browserCookies: any BrowserCookieReading,
        environment: @escaping @Sendable (String) -> String?,
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date
    ) -> DataSource {
        let fetcher: any Fetching = switch definition.fetch {
        case .http(let request):
            HTTPFetcher(request: request, network: network, now: now)
        case .httpSteps(let steps):
            HTTPStepsFetcher(steps: steps, network: network, now: now)
        case .jsonRpc(let call):
            JSONRPCFetcher(call: call, cliExecutor: makeCLIExecutor(CLICall(cli: call.cli)), makeTransport: makeTransport)
        case .cli(let call):
            CLIFetcher(call: call, makeExecutor: makeCLIExecutor)
        case .command(let call):
            CommandFetcher(call: call, makeExecutor: makeCommandExecutor)
        case .file(let call):
            FileFetcher(call: call, homeDirectory: homeDirectory, environment: environment)
        case .localServer(let call):
            LocalServerFetcher(call: call, commands: makeCommandExecutor(ProcessEnvironment()), network: localNetwork,
                               processPaths: processPaths)
        case .cloudWatch(let call):
            CloudWatchFetcher(call: call, client: cloudWatch, catalog: priceCatalog, now: now)
        case .directory(let call):
            DirectoryFetcher(call: call, homeDirectory: homeDirectory, environment: environment)
        }

        let mapper: any Reading = switch definition.mapping {
        case .json(let mapping): JSONMapper(mapping: mapping, now: now)
        case .text(let mapping): TextMapper(mapping: mapping, now: now)
        case .script(let mapping): ScriptMapper(file: mapping.file, source: scripts(mapping.file), values: mapping.values, now: now)
        }

        var refresher: (any CredentialRefreshing)?
        var lookup = definition.credential
        if case .refreshing(let base, let refresh)? = lookup {
            refresher = switch refresh {
            case .oauth2(let oauth): OAuth2Refresher(refresh: oauth, network: network, now: now)
            case .cli(let call): CLIRefresher(call: call, executor: makeCLIExecutor(call))
            }
            lookup = base
        }

        let readers = Readers(environment: environment, homeDirectory: homeDirectory, security: security,
                              secrets: secrets, providerId: providerId, browserCookies: browserCookies)
        return DataSource(
            definition: definition,
            providerId: providerId,
            credentials: lookup.map { readers.reader(for: $0) },
            refresher: refresher,
            fetcher: fetcher,
            mapper: mapper,
            contextFiles: definition.context.mapValues {
                JSONFileReader(file: $0, homeDirectory: homeDirectory, environment: environment)
            },
            recoveries: definition.recover.mapValues { recovery -> any Recovering in
                switch recovery {
                case .patchJSONFile(let path, let keys, let value):
                    JSONFilePatch(path: path, keys: keys, value: value, homeDirectory: homeDirectory, environment: environment)
                }
            },
            requiredFiles: definition.requiresFiles.map {
                Paths.expand($0, homeDirectory: homeDirectory, environment: environment)
            },
            now: now
        )
    }

    private struct Readers {
        let environment: @Sendable (String) -> String?
        let homeDirectory: URL
        let security: KeychainReader.Security
        let secrets: (any SecretStore)?
        let providerId: String
        let browserCookies: any BrowserCookieReading

        func reader(for lookup: CredentialLookup) -> any CredentialFinding {
            switch lookup {
            case .environment(let name):
                EnvironmentReader(name: name, environment: environment)
            case .jsonFile(let file):
                JSONFileReader(file: file, homeDirectory: homeDirectory, environment: environment)
            case .keychain(let item):
                KeychainReader(item: item, security: security)
            case .setting(let name):
                SettingReader(name: name, providerId: providerId, secrets: secrets)
            case .refined(let base, let refinement):
                RefinedReader(base: reader(for: base), refinement: refinement)
            case .sqlite(let database):
                SQLiteReader(file: database, homeDirectory: homeDirectory, environment: environment)
            case .browserCookies(let query):
                BrowserCookieReader(query: query, cookies: browserCookies)
            case .firstOf(let lookups):
                FirstOfReader(readers: lookups.map { reader(for: $0) })
            case .refreshing(let base, _):
                // A refresh nested inside `firstOf` is refreshed by the outer
                // data source only; reading still works.
                reader(for: base)
            }
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

    func recover() -> Bool {
        let url = URL(fileURLWithPath: Paths.expand(path, homeDirectory: homeDirectory, environment: environment))
        guard let data = try? Data(contentsOf: url),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        let cliDirectory = CLIWorkingDirectory.resolve().path
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
