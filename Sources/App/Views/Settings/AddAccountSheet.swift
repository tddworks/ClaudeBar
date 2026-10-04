import SwiftUI
import AppKit
import Domain
import Providers

/// *Add Account*: how (the definition's ways) → verify (who it is, then a
/// first fetch) → an optional name. Nothing is added until ClaudeBar knows
/// who the login is; *Add anyway* exists only after that.
struct AddAccountSheet: View {
    let provider: Provider
    let monitor: QuotaMonitor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    private enum Step {
        case how
        case form
        case signingIn(Task<Void, Never>)
        case verify(Account, fetch: FetchCheck)
        case name(Account)
        case failed(String)
    }

    private enum FetchCheck {
        case running
        case passed
        case failed(String)
    }

    @State private var step: Step = .how
    @State private var name = ""
    @State private var entered: [String: String] = [:]

    private var text: AccountsCardText { AccountsCardText(provider: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add \(provider.name) Account").font(.title3.bold()).foregroundStyle(theme.textPrimary)
            content
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if text.ways.count == 1, let only = text.ways.first { start(only.way) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .how:
            Text("How do you want to add it?")
                .font(.system(size: 12, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
            ForEach(text.ways, id: \.label) { way in
                Button { start(way.way) } label: {
                    Label(way.label, systemImage: way.way == .signIn ? "globe" : way.way == .folder ? "folder" : "key")
                        .font(.system(size: 13, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.glassBackground))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }

        case .form:
            ForEach(text.fields) { setting in
                SettingField(setting: setting, value: Binding(
                    get: { setting.value(from: entered[setting.id]) },
                    set: { entered[setting.id] = $0 }
                ))
            }
            Text("Kept for this account only. Keys are saved in your Keychain.")
                .font(.caption).foregroundStyle(theme.textSecondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { addFromForm() }.keyboardShortcut(.defaultAction)
            }

        case .signingIn(let task):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…").foregroundStyle(theme.textPrimary)
            }
            Text("ClaudeBar made a new folder for this login. Your usual \(provider.name) login isn't touched.")
                .font(.callout).foregroundStyle(theme.textSecondary)
            HStack { Spacer(); Button("Cancel") { task.cancel(); step = .how }.keyboardShortcut(.cancelAction) }

        case .verify(let account, let fetch):
            if account.madeBy == .form {
                check(true, "Saved for this account")
            } else {
                check(true, "Found a login")
                check(true, "Signed in as \(account.accountEmail ?? account.displayName)")
            }
            switch fetch {
            case .running:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Fetching usage…") }
            case .passed:
                check(true, "Fetched usage")
            case .failed(let reason):
                check(false, reason)
            }
            HStack {
                if case .failed = fetch {
                    Button("Remove") { provider.remove(account); monitor.removeProvider(id: account.id); dismiss() }
                    Spacer()
                    Button("Retry") { verify(account) }
                    // Only a login ClaudeBar knows the owner of may stay unchecked.
                    if account.madeBy != .form {
                        Button("Add anyway") { name = account.accountEmail ?? ""; step = .name(account) }
                    }
                } else {
                    Spacer()
                    Button("Next") { name = account.accountEmail ?? ""; step = .name(account) }
                        .keyboardShortcut(.defaultAction)
                        .disabled({ if case .running = fetch { return true }; return false }())
                }
            }

        case .name(let account):
            Text("Name (optional)").font(.callout).foregroundStyle(theme.textSecondary)
            TextField(account.accountEmail ?? "Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Done") {
                    provider.rename(account, to: name == account.accountEmail ? "" : name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

        case .failed(let message):
            check(false, message)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Try Again") { step = .how }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func check(_ passed: Bool, _ line: String) -> some View {
        Label {
            Text(line).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? theme.statusHealthy : theme.statusCritical)
        }
    }

    private func start(_ way: AddAccountWay) {
        switch way {
        case .signIn:
            let task = Task { @MainActor in
                do {
                    let account = try await provider.signIn()
                    added(account)
                } catch is CancellationError {
                    step = .how
                } catch {
                    if !Task.isCancelled { step = .failed(error.localizedDescription) }
                }
            }
            step = .signingIn(task)
        case .folder:
            chooseFolder()
        case .form:
            step = .form
        }
    }

    private func addFromForm() {
        do {
            added(try provider.addAccount(filling: entered))
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Add Account"
        panel.message = "Choose the folder this \(provider.name) login lives in."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                added(try provider.addAccount(signedInAt: url))
            } catch {
                step = .failed(error.localizedDescription)
            }
        }
    }

    private func added(_ account: Account) {
        monitor.addProvider(account)
        verify(account)
    }

    private func verify(_ account: Account) {
        step = .verify(account, fetch: .running)
        Task { @MainActor in
            do {
                try await account.refresh()
                step = .verify(account, fetch: .passed)
            } catch {
                step = .verify(account, fetch: .failed(error.localizedDescription))
            }
        }
    }
}
