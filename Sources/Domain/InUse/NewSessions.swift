import Foundation
import Mockable
import Observation
import Providers
import Quotas

/// The shell the lines are written for.
public enum LoginShell: String, CaseIterable, Sendable {
    case zsh, bash, fish

    /// The person's login shell, from `$SHELL` — zsh, macOS's own, when unknown.
    public static func login(_ path: String? = ProcessInfo.processInfo.environment["SHELL"]) -> LoginShell {
        let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return LoginShell(rawValue: name) ?? .zsh
    }
}

/// The lines in the person's shell that start each CLI on the login in use —
/// what `NewSessions` needs from the disk.
@Mockable
public protocol ShellLines: Sendable {
    /// The lines as they would be written for `shell`.
    func lines(for shell: LoginShell) -> String
    /// The file they go in.
    func file(for shell: LoginShell) -> URL
    func isInstalled(_ shell: LoginShell) -> Bool
    func install(_ shell: LoginShell) throws
    func remove(_ shell: LoginShell) throws
}

/// *New terminal sessions* — which login each CLI starts with, and the shell
/// lines that make the choice count. A login chosen before the lines are in
/// the shell waits for them, so a switch never silently does nothing; the
/// plain login needs no lines and is never kept waiting.
@MainActor
@Observable
public final class NewSessions {
    /// The products whose new sessions can be chosen — those with `inUse`.
    public let products: [Provider]
    private let shellLines: any ShellLines
    private let announcer: (any InUseAnnouncer)?
    /// A login's status as every surface reads it (the person's policy, hidden
    /// quotas left out): a login is worth moving off only when it reads low.
    private let readStatus: @MainActor (Account) -> QuotaStatus?

    /// The shell the lines are for — the login shell until the person picks another.
    public var shell: LoginShell {
        didSet { isSetUp = shellLines.isInstalled(shell) }
    }
    /// Whether the lines are in `shell`'s file.
    public private(set) var isSetUp: Bool
    /// The login chosen before the lines were there.
    public private(set) var waiting: Account?
    /// What went wrong last, in the person's words.
    public private(set) var problem: String?

    public init(products: [Provider], shellLines: any ShellLines, announcer: (any InUseAnnouncer)? = nil,
                shell: LoginShell = .login(), status: @escaping @MainActor (Account) -> QuotaStatus? = { $0.status }) {
        self.readStatus = status
        self.products = products.filter { $0.inUse != nil }
        self.shellLines = shellLines
        self.announcer = announcer
        self.shell = shell
        self.isSetUp = shellLines.isInstalled(shell)
    }

    /// What a product's strip shows: the setup a choice waits for, the login
    /// worth moving to, or the login in use. `nil` when there is no choice to offer.
    public func state(of product: Provider) -> State? {
        guard let inUse = product.inUse, inUse.offersChoice else { return nil }
        if isWaiting(in: product) { return .waitingForSetup }
        if let better = inUse.worthSwitching(reading: { self.readStatus($0) ?? .healthy }) { return .worthSwitching(from: inUse.login, to: better) }
        return .using(inUse.login)
    }

    public enum State: Equatable {
        case waitingForSetup
        case worthSwitching(from: Account, to: Account)
        /// The login in use.
        case using(Account)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.waitingForSetup, .waitingForSetup): true
            case let (.worthSwitching(a, b), .worthSwitching(c, d)): a === c && b === d
            case let (.using(a), .using(b)): a === b
            default: false
            }
        }
    }

    /// The CLIs the lines wrap — `claude`, `codex` — each once, however many
    /// products run it.
    public var commands: [String] {
        products.compactMap { $0.inUse?.command.name }.reduce(into: []) { kept, name in
            if !kept.contains(name) { kept.append(name) }
        }
    }

    /// The lines as the setup shows them, and the file they go in.
    public var lines: String { shellLines.lines(for: shell) }
    public var file: URL { shellLines.file(for: shell) }

    /// The product `providerId` names, when its new sessions can be chosen.
    public func product(_ providerId: String) -> Provider? {
        products.first { $0.id == providerId }
    }

    /// Whether a choice for `product` waits for the setup.
    public func isWaiting(in product: Provider) -> Bool {
        waiting?.providerId == product.id
    }

    /// Whether a choice for this login's product waits for the setup.
    public func isWaiting(for login: Account) -> Bool {
        waiting?.providerId == login.providerId
    }

    /// *Use for new sessions* — at once when the lines are there (or for the
    /// plain login), else once they are set up.
    public func use(_ account: Account) {
        isSetUp = shellLines.isInstalled(shell)
        guard isSetUp || account.isDefault else {
            waiting = account
            return
        }
        apply(account)
    }

    /// What `claudebar://use?provider=…&account=…` did.
    public enum LinkOutcome: Equatable {
        case used
        case waitingForSetup
        /// No such product, or no such login that new sessions can start on.
        case unknown
    }

    /// `claudebar://use` — the login a link names, by its product's id and its name.
    public func use(providerId: String, account name: String) -> LinkOutcome {
        guard let product = product(providerId), let account = product.accounts.named(name), product.inUse?.canBeInUse(account) == true else {
            return .unknown
        }
        use(account)
        return isWaiting(in: product) ? .waitingForSetup : .used
    }

    /// After a login's refresh: *Switch when low* moves new sessions, or a
    /// login worth moving to is announced — once per low.
    public func review(_ refreshed: Account) async {
        guard let product = product(refreshed.providerId), let inUse = product.inUse,
              let notice = try? inUse.review(reading: { self.readStatus($0) ?? .healthy }) else { return }
        await announcer?.announce(InUseAlert(notice, of: product))
    }

    /// *Add to ~/.zshrc* — writes the lines, then makes the waiting choice.
    public func setUp() {
        do {
            try shellLines.install(shell)
            isSetUp = true
            if let waiting { apply(waiting) }
            waiting = nil
        } catch {
            problem = "ClaudeBar couldn't write \(file.path): \(error.localizedDescription)"
        }
    }

    /// *Copy — I'll add it* — the person adds the lines; the choice is made
    /// now. Returns the lines to copy.
    public func setUpByHand() -> String {
        if let waiting { apply(waiting) }
        waiting = nil
        return lines
    }

    public func cancel() {
        waiting = nil
    }

    /// *Remove* — takes the lines out, and every CLI goes back to its plain login.
    public func turnOff() {
        do {
            try shellLines.remove(shell)
            isSetUp = false
            for product in products {
                try? product.inUse?.use(product.defaultAccount)
            }
        } catch {
            problem = "ClaudeBar couldn't change \(file.path): \(error.localizedDescription)"
        }
    }

    private func apply(_ account: Account) {
        do {
            guard let inUse = product(account.providerId)?.inUse else {
                throw UsageError.executionFailed("This login's product can't choose a login for new sessions.")
            }
            try inUse.use(account)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
