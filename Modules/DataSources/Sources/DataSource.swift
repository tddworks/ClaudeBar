import Diagnostics
import Quotas
import Foundation

/// ONE type that fetches for every provider: its definition, made live by
/// `DataSources.make` with only the connection its fetch needs.
///
/// `fetchUsage()` is *Fetching usage data…*: look up the key, fetch, map.
/// `fetchResponse()` is *Test Connection*: it stops before mapping, so a person
/// with nothing mapped yet can see what came back.
public struct DataSource: Sendable {
    public let definition: DataSourceDefinition
    public let providerId: String

    private let credentials: (any CredentialFinding)?
    private let refresher: (any CredentialRefreshing)?
    private let fetcher: any Fetching
    private let mapper: any Reading
    private let contextFiles: [String: JSONFileReader]
    private let recoveries: [String: any Recovering]
    private let requiredFiles: [String]
    private let memory: UsageMemory
    private let now: @Sendable () -> Date

    init(
        definition: DataSourceDefinition,
        providerId: String,
        credentials: (any CredentialFinding)?,
        refresher: (any CredentialRefreshing)?,
        fetcher: any Fetching,
        mapper: any Reading,
        contextFiles: [String: JSONFileReader],
        recoveries: [String: any Recovering],
        requiredFiles: [String] = [],
        now: @escaping @Sendable () -> Date
    ) {
        self.definition = definition
        self.providerId = providerId
        self.credentials = credentials
        self.refresher = refresher
        self.fetcher = fetcher
        self.mapper = mapper
        self.contextFiles = contextFiles
        self.recoveries = recoveries
        self.requiredFiles = requiredFiles
        self.memory = UsageMemory()
        self.now = now
    }

    public var kind: String { definition.kind }

    /// How long a fetched usage is served again — also the provider's
    /// background refresh floor while this data source is active.
    public var cacheTTL: TimeInterval? { definition.cache?.ttl }

    /// The data source that takes over when this one finds no key — its
    /// `fallbackOn.authenticationRequired` — or `nil` when it has its key.
    public var handOffWithoutKey: String? {
        hasKey ? nil : definition.fallbackOn[UsageError.authenticationRequired.tag]
    }

    /// Whether the key lookup finds a key — *OAuth credentials found*.
    /// `true` for a data source that needs none.
    public var hasKey: Bool {
        guard let credentials else { return true }
        return (try? credentials.find()) != nil
    }

    /// *Configured*: the files it needs exist, the key answers (when one is
    /// needed), belongs to the expected account, and the CLI exists.
    public func isReady() async -> Bool {
        guard requiredFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { return false }
        var credential: Credential?
        if let credentials {
            guard let found = try? credentials.find() else { return false }
            credential = found.credential
        }
        guard isExpectedLogin(credential) else { return false }
        return fetcher.isReady()
    }

    /// What an identity field holds — the account id, the email — read from
    /// the credential or a context file. Never a token; `nil` when nothing
    /// answers.
    public func value(of field: IdentityField) -> String? {
        let credential = (try? credentials?.find())?.credential
        return read(field, credential: credential.map { Credential(Self.withoutSecrets($0.values)) })
    }

    /// Looks up the key and fetches. Nothing is mapped and nothing is saved.
    /// Throws a `DataSourceError` naming the step that failed.
    public func fetchResponse() async throws -> Response {
        try await fetch().response
    }

    /// *Fetching usage data…* — `mapping.read(fetchResponse())`, served from
    /// the cache while it is fresh, and refused without a request while a
    /// rate limit lasts. Throws a `DataSourceError` naming the step that failed.
    public func fetchUsage() async throws -> UsageSnapshot {
        if let ttl = cacheTTL, let cached = memory.snapshot(within: ttl, now: now()) {
            return cached
        }
        if let retryAt = memory.rateLimit(now: now()) {
            throw DataSourceError(.fetch, .rateLimited(retryAt: retryAt))
        }
        do {
            let usage = try await fetchAndRead(recovering: true)
            if cacheTTL != nil { memory.remember(usage, at: now()) }
            return usage
        } catch let error as DataSourceError {
            if case .rateLimited(let retryAt) = error.reason { memory.remember(rateLimitUntil: retryAt) }
            throw error
        }
    }

    /// *Map fields*' live card: reads a response already fetched.
    public func read(_ response: Response) throws -> UsageSnapshot {
        try read(response, credential: nil)
    }

    // MARK: - Private

    private func fetchAndRead(recovering: Bool) async throws -> UsageSnapshot {
        let (response, credential) = try await fetch()
        do {
            return try read(response, credential: credential)
        } catch let failure as DataSourceError {
            guard recovering, let recovery = recoveries[failure.reason.tag], recovery.recover() else { throw failure }
            AppLog.probes.info("\(providerId) \(kind): recovered from \(failure.reason.tag), trying once more")
            return try await fetchAndRead(recovering: false)
        }
    }

    private func read(_ response: Response, credential: Credential?) throws -> UsageSnapshot {
        let facts = MappingFacts(
            credential: visibleCredential(credential),
            context: contextFiles.mapValues { $0.fields() }
        )
        do {
            return try mapper.read(response, facts: facts, providerId: providerId)
        } catch {
            throw DataSourceError.wrap(error, as: .mapping)
        }
    }

    /// What a mapping may read of the credential — never a token. A script
    /// sees only the values it names.
    private func visibleCredential(_ credential: Credential?) -> [String: String] {
        guard let credential else { return [:] }
        let values = Self.withoutSecrets(credential.values)
        if case .script(let script) = definition.mapping {
            return values.filter { script.credential.contains($0.key) }
        }
        return values
    }

    private static func withoutSecrets(_ values: [String: String]) -> [String: String] {
        let secret: Set = ["token", "refreshToken", "idToken"]
        return values.filter { !secret.contains($0.key) }
    }

    private func read(_ field: IdentityField, credential: Credential?) -> String? {
        switch field {
        case .credential(let name): credential?[name]
        case .context(let file, let field): contextFiles[file]?.fields()[field]
        }
    }

    private func isExpectedLogin(_ credential: Credential?) -> Bool {
        guard let identity = definition.identity else { return true }
        return read(identity.field, credential: credential) == identity.equals
    }

    /// Fails closed when the login now belongs to another account.
    private func checkIdentity(_ credential: Credential?) throws {
        guard let identity = definition.identity else { return }
        guard isExpectedLogin(credential) else {
            throw DataSourceError(.lookup, .sessionExpired(hint: identity.hint))
        }
    }

    private func fetch() async throws -> (response: Response, credential: Credential?) {
        for file in requiredFiles where !FileManager.default.fileExists(atPath: file) {
            // ClaudeBar never starts a login itself (#216).
            AppLog.probes.error("\(providerId) \(kind): no \(file) — refusing to run")
            throw DataSourceError(.lookup, .authenticationRequired)
        }
        var found = try lookUp()
        try checkIdentity(found?.credential)
        let result = try await fetchWith(&found)
        if definition.identity != nil {
            try checkIdentity((try? credentials?.find())?.credential)
        }
        return result
    }

    private func fetchWith(_ found: inout FoundCredential?) async throws -> (response: Response, credential: Credential?) {

        if let refresher, let current = found, refresher.isDue(current.credential) {
            do {
                found = try await refreshed(current, by: refresher)
            } catch let error as DataSourceError {
                if let rotated = rotated(since: current) {
                    // Another program — the CLI that owns the credential —
                    // already refreshed it. Its token is the one to use.
                    found = rotated
                } else if error.reason.isSessionExpired {
                    throw error
                } else {
                    // A proactive refresh that fails is not fatal: the token
                    // we have may still work.
                    AppLog.probes.warning("\(providerId) \(kind): refresh failed, trying the current token")
                }
            }
        }

        do {
            return (try await fetcher.fetch(with: found?.credential), found?.credential)
        } catch let refused as HTTPStatusError {
            guard let refresher, let current = found, refresher.retryStatuses.contains(refused.status) else {
                throw fetchError(refused)
            }
            AppLog.probes.info("\(providerId) \(kind): HTTP \(refused.status), refreshing the token once")
            let renewed: FoundCredential
            do {
                renewed = try await refreshed(current, by: refresher)
            } catch {
                guard let rotated = rotated(since: current) else { throw error }
                renewed = rotated
            }
            do {
                return (try await fetcher.fetch(with: renewed.credential), renewed.credential)
            } catch {
                throw fetchError(error)
            }
        } catch {
            throw fetchError(error)
        }
    }

    private func lookUp() throws -> FoundCredential? {
        guard let credentials else { return nil }
        let found: FoundCredential?
        do {
            found = try credentials.find()
        } catch {
            throw DataSourceError.wrap(error, as: .lookup)
        }
        guard let found else {
            throw DataSourceError(.lookup, .authenticationRequired)
        }
        return found
    }

    /// The credential looked up again, when its token is no longer `current`'s.
    private func rotated(since current: FoundCredential) -> FoundCredential? {
        guard let fresh = try? credentials?.find(),
              fresh.credential.token != current.credential.token else { return nil }
        AppLog.probes.info("\(providerId) \(kind): the credential changed on disk; using the new one")
        return fresh
    }

    /// Refreshes the token and writes it back where it was found — or, when
    /// its owner renewed it, reads it again from there.
    private func refreshed(_ found: FoundCredential, by refresher: any CredentialRefreshing) async throws -> FoundCredential {
        var renewed = found
        do {
            renewed.credential = try await refresher.refresh(found.credential)
        } catch {
            throw DataSourceError.wrap(error, as: .lookup)
        }
        guard refresher.writesBack else {
            guard let reread = try? credentials?.find() else { throw DataSourceError(.lookup, .authenticationRequired) }
            return reread
        }
        renewed.save?(renewed.credential)
        return renewed
    }

    /// A worker's failure, worded by the definition.
    private func fetchError(_ error: Error) -> DataSourceError {
        guard let failure = error as? any ReportedFailure else { return DataSourceError.wrap(error, as: .fetch) }
        return DataSourceError(.fetch, definition.reason(for: failure))
    }
}

extension UsageError {
    var isSessionExpired: Bool {
        if case .sessionExpired = self { return true }
        return false
    }

    /// The name a definition uses for this failure — `fallbackOn` and `recover` keys.
    public var tag: String {
        switch self {
        case .cliNotFound: "cliNotFound"
        case .authenticationRequired: "authenticationRequired"
        case .sessionExpired: "sessionExpired"
        case .parseFailed: "parseFailed"
        case .timeout: "timeout"
        case .noData: "noData"
        case .updateRequired: "updateRequired"
        case .folderTrustRequired: "folderTrustRequired"
        case .executionFailed: "executionFailed"
        case .subscriptionRequired: "subscriptionRequired"
        case .rateLimited: "rateLimited"
        }
    }
}

// MARK: - The workers' roles (internal: the factory picks them)

/// A credential found, and how to write a refreshed one back where it came from.
struct FoundCredential: Sendable {
    var credential: Credential
    let save: (@Sendable (Credential) -> Void)?
}

/// What a mapping may read besides the response: the credential values it was
/// allowed to see, and the fields of each context file.
struct MappingFacts: Sendable {
    var credential: [String: String] = [:]
    var context: [String: [String: String]] = [:]
}

protocol CredentialFinding: Sendable {
    /// `nil` when nothing answered — *Key needed*.
    func find() throws -> FoundCredential?
}

protocol CredentialRefreshing: Sendable {
    var retryStatuses: [Int] { get }
    /// Whether the renewed credential is ClaudeBar's to write back, or the
    /// owner wrote it and it is read again.
    var writesBack: Bool { get }
    func isDue(_ credential: Credential) -> Bool
    func refresh(_ credential: Credential) async throws -> Credential
}

protocol Fetching: Sendable {
    func isReady() -> Bool
    func fetch(with credential: Credential?) async throws -> Response
}

protocol Reading: Sendable {
    func read(_ response: Response, facts: MappingFacts, providerId: String) throws -> UsageSnapshot
}

/// A fix tried once when the mapping reports a failure. `true` when it changed
/// something worth trying again for.
protocol Recovering: Sendable {
    func recover() -> Bool
}

/// An HTTP answer outside 2xx, kept with its status so a refresh can be tried.
struct HTTPStatusError: ReportedFailure {
    let status: Int
    let reason: UsageError

    var fact: ErrorFact? {
        if case .rateLimited = reason { return nil }
        return .httpStatus(status)
    }
}

/// The last usage and a rate limit's end, kept between refreshes.
final class UsageMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var last: (usage: UsageSnapshot, at: Date)?
    private var retryAt: Date?

    func snapshot(within ttl: TimeInterval, now: Date) -> UsageSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let last, now.timeIntervalSince(last.at) < ttl else { return nil }
        return last.usage
    }

    func remember(_ usage: UsageSnapshot, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        last = (usage, date)
    }

    func rateLimit(now: Date) -> Date? {
        lock.lock(); defer { lock.unlock() }
        guard let retryAt, retryAt > now else {
            retryAt = nil
            return nil
        }
        return retryAt
    }

    func remember(rateLimitUntil date: Date) {
        lock.lock(); defer { lock.unlock() }
        retryAt = date
    }
}
