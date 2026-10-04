import AppKit
import SwiftUI
import Domain
import Infrastructure
import Providers

/// A provider someone made: *Export…* it to share (the file names its key,
/// never holds it), or *Delete* it — its definition file and saved key go, and
/// it leaves the lineup. Built-ins can only be disabled.
struct CustomProviderCard: View {
    let provider: Provider
    let monitor: QuotaMonitor
    let onDeleted: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var confirming = false
    @State private var error: String?

    var body: some View {
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom provider")
                        .font(.system(size: 12, weight: .semibold, design: theme.fontDesign))
                    Text("Export shares it without keys — they stay in your Keychain. Deleting removes it and forgets its key.")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                    if let error {
                        Text(error)
                            .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.statusWarning)
                    }
                }
                Spacer()
                Button("Export…", action: export)
                Button("Delete Provider…", role: .destructive) { confirming = true }
            }
        }
        .confirmationDialog("Delete \(provider.name)?", isPresented: $confirming) {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(provider.name).claudebar-provider.json"
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try provider.definition.exported().write(to: url, options: .atomic)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete() {
        do {
            try ProviderCatalog().remove(provider.id)
        } catch {
            self.error = error.localizedDescription
            return
        }
        ProviderVault().delete("apiKey", provider: provider.id)
        for account in provider.accounts {
            monitor.removeProvider(id: account.id)
        }
        Providers.unregister(custom: provider.id)
        onDeleted()
    }
}
