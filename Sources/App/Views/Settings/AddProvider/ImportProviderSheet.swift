import SwiftUI
import DataSources
import Domain
import Infrastructure
import Providers

/// *Import provider* — USER_JOURNEYS moment 11. Before anything is saved or
/// run it says where the key will be sent, shows every command a CLI provider
/// runs (Add waits until the person trusts it), and asks for the keys it needs
/// (USER_JOURNEYS F10). *Add* saves it as Custom, with no restart.
struct ImportProviderSheet: View {
    let monitor: QuotaMonitor
    let review: ImportReview
    let onDone: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var keys: [String: String] = [:]
    @State private var trustsCommands = false
    @State private var testText: String?
    @State private var testFailed = false
    @State private var isTesting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: review.definition.profile.look.symbol ?? "square.and.arrow.down")
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import provider")
                        .font(theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    Text(review.definition.profile.name)
                        .font(theme.font(size: 17, weight: .bold))
                }
                Spacer()
                Text("CUSTOM")
                    .font(theme.font(size: 8, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.glassBorder.opacity(0.6)))
            }

            Divider()

            if !review.sendsKeyTo.isEmpty {
                notice(
                    symbol: "arrow.up.forward.app",
                    text: "It will send your key to \(review.sendsKeyTo.joined(separator: ", ")). Only add it if you trust that address."
                )
            }

            if !review.runs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("IT RUNS")
                    ForEach(review.runs, id: \.self) { command in
                        Text(command)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(theme.glassBackground))
                    }
                    Toggle("I trust this command — ClaudeBar runs it with my rights each time it refreshes", isOn: $trustsCommands)
                        .font(theme.font(size: 10, weight: .medium))
                }
            }

            ForEach(review.needs, id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    label("KEY NEEDED — \(name == "apiKey" ? "API KEY" : name.uppercased())")
                    SecureField("Paste your own key", text: Binding(get: { keys[name] ?? "" }, set: { keys[name] = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Text("Kept in your Keychain — never in the provider's file.")
                        .font(theme.font(size: 9, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            HStack(spacing: 8) {
                Button(isTesting ? "Testing…" : "Test Connection", action: testConnection)
                    .disabled(isTesting || !canRun)
                if let testText {
                    Text(testText)
                        .font(theme.font(size: 10, weight: .semibold))
                        .foregroundStyle(testFailed ? theme.statusWarning : theme.statusHealthy)
                        .lineLimit(2)
                }
            }

            if let error {
                Text(error)
                    .font(theme.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.statusWarning)
            }

            Spacer()

            HStack {
                Button("Cancel", action: onDone)
                Spacer()
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 480, height: 440)
    }

    /// A CLI provider runs nothing — not even a test — until it is trusted.
    private var canRun: Bool { review.runs.isEmpty || trustsCommands }

    private var canAdd: Bool {
        canRun && review.needs.allSatisfy { !(keys[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func testConnection() {
        let definition = review.definition
        guard let source = definition.dataSource(definition.defaultDataSource) else { return }
        isTesting = true
        testText = nil
        Task {
            defer { isTesting = false }
            let live = DataSources.make(source, providerId: definition.id, scripts: ProviderFactory.builtInScripts,
                                        secrets: TypedKeys(values: keys))
            do {
                let response = try await live.fetchResponse()
                testFailed = false
                testText = DataSourceSectionText.testResult(.success(response))
            } catch let failure as DataSourceError {
                testFailed = true
                testText = DataSourceSectionText.testResult(.failure(failure))
            } catch {
                testFailed = true
                testText = error.localizedDescription
            }
        }
    }

    private func add() {
        do {
            let provider = try monitor.providers.import(review)
            let vault = ProviderVault()
            for (name, value) in keys where !value.isEmpty {
                vault.save(value, name, provider: provider.id)
            }
            Task { await monitor.refresh(providerId: provider.defaultAccount.id) }
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func notice(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(theme.statusWarning)
            Text(text)
                .font(theme.font(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(theme.font(size: 9, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
            .tracking(0.5)
    }
}

/// The keys typed while reviewing, for *Test Connection* before anything is saved.
private struct TypedKeys: SecretStore {
    let values: [String: String]

    func secret(_ name: String, provider: String) -> String? {
        values[name].flatMap { $0.isEmpty ? nil : $0 }
    }
}
