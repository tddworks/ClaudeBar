import SwiftUI
import AppKit
import Kit

/// Under a product's account chips: what `NewSessions.state(of:)` says —
/// the setup a choice waits for, the login worth moving to, or the login in
/// use as a menu to change it. It renders and tells; it decides nothing.
struct InUseStrip: View {
    let state: NewSessions.State
    @Environment(NewSessions.self) private var sessions
    @Environment(\.appTheme) private var theme
    private var settings: AppSettings { .shared }

    var body: some View {

        let _ = KitObservation.track()
        VStack(alignment: .leading, spacing: 8) {
            switch state.shape {
            case .waitingForSetup:
                InUseSetupCard()
            case let .worthSwitching(from, to):
                suggestion(from: from, to: to)
            case let .using(login):
                line(login)
            }
            if let problem = sessions.problem {
                Text(problem)
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.statusCritical)
            }
        }
    }

    /// "New terminal sessions use personal · Desktop & IDE keep their own login".
    private func line(_ login: Account) -> some View {
        (Text(Image(systemName: "terminal")) + Text(" New terminal sessions use ")
            + Text(settings.shown(login.displayName)).bold().foregroundColor(theme.textPrimary)
            + Text(" · Desktop & IDE keep their own login"))
            .font(theme.font(size: 10, weight: .medium))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestion(from: Account, to: Account) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill").foregroundStyle(theme.statusWarning)
            Text("\(settings.shown(from.displayName)) is low — \(settings.shown(to.displayName)) has \(to.percentLeft.map { "\(Int($0))%" } ?? "more") left")
                .font(theme.font(size: 11, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            InUseButton(title: "Use \(settings.shown(to.displayName))", prominent: true) { sessions.use(account: to) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.statusWarning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.statusWarning.opacity(0.4), lineWidth: 1))
    }
}

/// The one-time setup: the lines ClaudeBar adds to the shell, shown before
/// they are written.
struct InUseSetupCard: View {
    @Environment(NewSessions.self) private var sessions
    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        @Bindable var sessions = sessions
        VStack(alignment: .leading, spacing: 8) {
            Text("Let ClaudeBar choose the login?")
                .font(theme.font(size: 13, weight: .bold))
                .foregroundStyle(theme.textPrimary)
            Text("One time: ClaudeBar adds these lines to your shell. Each time you run \(sessions.commands.formatted(.list(type: .or))), they start on the login you chose here. Delete them to turn this off.")
                .font(theme.font(size: 11))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(LoginShell.allCases, id: \.self) { shell in
                    InUseButton(title: shell.tag, prominent: sessions.shell == shell) { sessions.shell = shell }
                }
            }
            ScrollView {
                Text(sessions.lines)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 130)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.glassBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            HStack(spacing: 6) {
                InUseButton(title: "Add to \(sessions.file.abbreviatingHome)", prominent: true) { sessions.setUp() }
                InUseButton(title: "Copy — I'll Add It", prominent: false) {
                    let lines = sessions.setUpByHand()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines, forType: .string)
                }
                Spacer(minLength: 0)
                InUseButton(title: "Cancel", prominent: false) { sessions.cancel() }
            }
            Text("Terminals already open pick it up in a new tab.")
                .font(theme.font(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.cardGradient))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
    }
}

/// Settings → Accounts: which login new terminal sessions use, the shell
/// lines that make it work, and *Switch when low*.
struct InUseSettingsSection: View {
    let inUse: InUse
    @Environment(NewSessions.self) private var sessions
    @Environment(\.appTheme) private var theme
    @State private var settingUp = false
    private var settings: AppSettings { .shared }

    var body: some View {

        let _ = KitObservation.track()
        let policy = inUse.switchWhenLow
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("New terminal sessions").font(.subheadline.bold()).foregroundStyle(theme.textPrimary)
            Text("The account marked IN USE above is the one `\(inUse.command.name)` starts with in your terminal. Sessions already running keep theirs; Claude Desktop and IDE extensions keep their own login.")
                .font(.caption).foregroundStyle(theme.textSecondary)

            if settingUp || sessions.isWaiting(login: inUse.login) {
                InUseSetupCard()
                    .onChange(of: sessions.isSetUp) { _, done in if done { settingUp = false } }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: sessions.isSetUp ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(sessions.isSetUp ? theme.statusHealthy : theme.textTertiary)
                    Text(sessions.isSetUp ? "Shell set up in \(sessions.file.abbreviatingHome)" : "Shell not set up yet")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                    Spacer()
                    if sessions.isSetUp {
                        Button("Remove") { sessions.turnOff() }.controlSize(.small)
                    } else {
                        Button("Set Up…") { settingUp = true }.controlSize(.small)
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switch when low").foregroundStyle(theme.textPrimary)
                    Text("New sessions move to the ticked login with the most left, and ClaudeBar tells you each time.")
                        .font(.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                Toggle("Switch when low", isOn: Binding(get: { policy.isOn }, set: { policy.isOn = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            if policy.isOn {
                HStack {
                    Text("When the login in use drops below").font(.caption).foregroundStyle(theme.textSecondary)
                    Picker("", selection: Binding(get: { policy.belowPercent }, set: { policy.belowPercent = $0 })) {
                        ForEach([5, 10, 20, 30], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ForEach(inUse.logins, id: \.id) { login in
                    Toggle(settings.shown(login.displayName), isOn: Binding(
                        get: { policy.mayPick(account: login) },
                        set: { policy.setMayPick(allowed: $0, account: login) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
        }
    }
}

/// "IN USE" — on the chip and the Settings row of the login new sessions start with.
struct InUseBadge: View {
    /// The badge's gap to a chip's edge on every side; its corners are the
    /// chip's radius less that gap.
    static let inset: CGFloat = 4

    /// A chip's height: a provider pill's, drawn the same way.
    static func chipHeight(in theme: any AppThemeProvider) -> CGFloat { 25 }
    @Environment(\.appTheme) private var theme

    /// The gap from the chip's edge: the inset, from the inside of its outline,
    /// which is stroked across the edge — half of it falls inside.
    static func gap(in theme: any AppThemeProvider) -> CGFloat { (inset + theme.cardBorderWidth / 2).rounded() }

    var body: some View {

        let _ = KitObservation.track()
        Text("IN USE")
            .font(theme.font(size: 8, weight: .heavy))
            .padding(.horizontal, 6)
            .frame(height: Self.chipHeight(in: theme) - 2 * Self.gap(in: theme))
            .foregroundStyle(theme.textPrimary)
            .background(RoundedRectangle(cornerRadius: max(theme.pillCornerRadius - Self.gap(in: theme), 2))
                .fill(theme.statusWarning.opacity(0.35)))
            .accessibilityLabel("In use for new terminal sessions")
    }
}

/// A small capsule button in the theme's colours.
struct InUseButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        Button(action: action) {
            Text(title)
                .font(theme.font(size: 10.5, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(prominent ? theme.textPrimary : theme.textSecondary)
                .background(Capsule().fill(prominent ? theme.accentPrimary.opacity(0.22) : theme.glassBackground))
                .overlay(Capsule().stroke(prominent ? theme.accentPrimary.opacity(0.6) : theme.glassBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    /// `~/.zshrc` rather than `/Users/you/.zshrc`.
    var abbreviatingHome: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
