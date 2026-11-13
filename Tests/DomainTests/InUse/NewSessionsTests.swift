import Foundation
import Testing
@testable import Domain
@testable import Infrastructure
@testable import Providers
import Quotas

/// *New terminal sessions*: choosing which login each CLI starts with, and
/// the shell lines that make the choice count.
@MainActor
@Suite
struct NewSessionsTests {
    /// The shell lines, kept in memory.
    private final class Lines: ShellLines, @unchecked Sendable {
        var installed: Set<LoginShell> = []
        var failing = false
        func lines(for shell: LoginShell) -> String { "# lines for \(shell.rawValue)" }
        func file(for shell: LoginShell) -> URL { URL(fileURLWithPath: "/Users/you/.\(shell.rawValue)rc") }
        func isInstalled(_ shell: LoginShell) -> Bool { installed.contains(shell) }
        func install(_ shell: LoginShell) throws {
            if failing { throw CocoaError(.fileWriteNoPermission) }
            installed.insert(shell)
        }
        func remove(_ shell: LoginShell) throws { installed.remove(shell) }
    }

    private let temp = FileManager.default.temporaryDirectory.appendingPathComponent("new-sessions-\(UUID().uuidString)")
    private let lines = Lines()

    /// Codex with its plain login and an added folder login, *work*.
    private func codex() -> Provider {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("settings.json")))
        let work = ProviderAccountConfig(accountId: "work", label: "work",
                                         probeConfig: ["folder": "/Users/you/.codex-work", "accountId": "work"])
        return try! ProviderFactory.make("codex", settings: settings, accounts: [work],
                                   loginsInUse: DiskLoginsInUse(root: temp.appendingPathComponent("in-use")))
    }

    @Test
    func `should start new sessions with the chosen login at once when the shell is set up`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        sessions.use(codex.accounts[1])

        #expect(codex.inUse?.isInUse(codex.accounts[1]) == true)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `should hold the chosen login until the shell is set up`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        sessions.use(codex.accounts[1])

        #expect(codex.inUse?.isInUse(codex.accounts[1]) != true)
        #expect(sessions.isWaiting(in: codex))
    }

    @Test
    func `should set up the shell and start new sessions with the held login when the person sets up`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .bash)
        sessions.use(codex.accounts[1])

        sessions.setUp()

        #expect(sessions.isSetUp)
        #expect(lines.installed == [.bash])
        #expect(codex.inUse?.isInUse(codex.accounts[1]) == true)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `should hand the person the shell lines and start new sessions with the held login when they set up by hand`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        let copied = sessions.setUpByHand()

        #expect(copied == "# lines for zsh")
        #expect(codex.inUse?.isInUse(codex.accounts[1]) == true)
    }

    @Test
    func `should keep the login in use as it was when the person cancels the setup`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        sessions.cancel()

        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `should start new sessions with the plain login without waiting for the shell setup`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])
        lines.installed = []

        sessions.use(codex.defaultAccount)

        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
        #expect(sessions.waiting == nil)
    }

    @Test
    func `should remove the shell lines and put every CLI back on its plain login when the person turns new sessions off`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        sessions.turnOff()

        #expect(!sessions.isSetUp)
        #expect(lines.installed.isEmpty)
        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
    }

    @Test
    func `should name the shell file and keep the login held when the setup can't write it`() {
        lines.failing = true
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        sessions.setUp()

        #expect(sessions.problem?.contains("/Users/you/.zshrc") == true)
        #expect(sessions.isWaiting(in: codex))
    }

    // MARK: - What the strip shows

    @Test
    func `should show the login new sessions start with`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        #expect(sessions.state(of: codex) == .using(codex.defaultAccount))
    }

    @Test
    func `should show the setup while a chosen login waits for it`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)
        sessions.use(codex.accounts[1])

        #expect(sessions.state(of: codex) == .waitingForSetup)
    }

    @Test
    func `should show nothing for a provider with one login`() throws {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("one.json")))
        let alone = try ProviderFactory.make("codex", settings: settings,
                                       loginsInUse: DiskLoginsInUse(root: temp.appendingPathComponent("in-use")))
        let sessions = NewSessions(products: [alone], shellLines: lines, shell: .zsh)

        #expect(sessions.state(of: alone) == nil)
    }

    @Test
    func `should name each CLI once, however many providers run it`() {
        let sessions = NewSessions(products: [codex(), codex()], shellLines: lines, shell: .zsh)

        #expect(sessions.commands == ["codex"])
    }

    // MARK: - claudebar://use

    @Test
    func `should start new sessions with the login a link names by provider and name`() {
        lines.installed = [.zsh]
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        #expect(sessions.use(providerId: "codex", account: "work") == .used)
        #expect(codex.inUse?.isInUse(codex.accounts[1]) == true)
    }

    @Test
    func `should hold the login a link names until the shell is set up`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        #expect(sessions.use(providerId: "codex", account: "work") == .waitingForSetup)
    }

    @Test
    func `should do nothing for a link to an unknown provider or login`() {
        let codex = codex()
        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh)

        #expect(sessions.use(providerId: "gemini", account: "work") == .unknown)
        #expect(sessions.use(providerId: "codex", account: "someone") == .unknown)
        #expect(codex.inUse?.isInUse(codex.defaultAccount) == true)
    }

    // MARK: - The alert a notice becomes

    @Test
    func `should link a switch's alert back to the earlier login and a suggestion's alert on to the suggested one`() {
        let codex = codex()
        let (me, work) = (codex.defaultAccount, codex.accounts[1])

        let switched = InUseAlert(.switched(from: me, to: work), of: codex)
        let suggested = InUseAlert(.worthSwitching(from: me, to: work), of: codex)

        #expect(switched.kind == .switched && switched.to == "work")
        #expect(switched.link.absoluteString == "claudebar://use?provider=codex&account=default")
        #expect(suggested.kind == .worthSwitching)
        #expect(suggested.link.absoluteString == "claudebar://use?provider=codex&account=work")
    }

    @Test
    func `should list only providers whose new sessions can start with a chosen login`() throws {
        let settings = JSONSettingsRepository(store: JSONSettingsStore(fileURL: temp.appendingPathComponent("s.json")))
        let gemini = try ProviderFactory.make("gemini", settings: settings)
        let codex = codex()

        let sessions = NewSessions(products: [gemini, codex], shellLines: lines, shell: .zsh)

        #expect(sessions.products.map(\.id) == ["codex"])
        #expect(sessions.product("codex") === codex)
        #expect(sessions.product("gemini") == nil)
    }

    // MARK: - Worth switching reads the status every surface reads

    /// A 5-hour quota with `left` percent left and `elapsed` percent of its window gone.
    private func paced(_ type: QuotaType, left: Double, elapsed: Double) -> UsageQuota {
        let length: TimeInterval = 5 * 3600
        return UsageQuota(percentRemaining: left, quotaType: type, providerId: "codex",
                          resetsAt: Date().addingTimeInterval(length * (100 - elapsed) / 100), windowDuration: length)
    }

    @Test
    func `should suggest no switch when only a hidden quota reads low`() {
        lines.installed = [.zsh]
        let codex = codex()
        let me = codex.accounts[0], work = codex.accounts[1]
        // The watched session lasts; the hidden weekly runs out in 20 minutes.
        me.snapshot = UsageSnapshot(providerId: "codex", quotas: [
            paced(.session, left: 19, elapsed: 97.3), paced(.weekly, left: 40, elapsed: 10),
        ], capturedAt: Date())
        work.snapshot = UsageSnapshot(providerId: "codex", quotas: [paced(.session, left: 90, elapsed: 10)], capturedAt: Date())
        let hidden: Set<String> = [QuotaType.weekly.quotaKey]

        let sessions = NewSessions(products: [codex], shellLines: lines, shell: .zsh,
                                   status: { $0.snapshot?.hiding(hidden).overallStatus(under: .paceAware) })

        #expect(sessions.state(of: codex) == .using(me))
    }
}
