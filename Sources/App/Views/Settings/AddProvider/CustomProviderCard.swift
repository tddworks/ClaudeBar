import AppKit
import SwiftUI
import Kit

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

        let _ = KitObservation.track()
        SettingsCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom provider")
                        .font(theme.font(size: 12, weight: .semibold))
                    Text("Export shares it without keys — they stay in your Keychain. Deleting removes it and forgets its key.")
                        .font(theme.font(size: 10, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                    if let error {
                        Text(error)
                            .font(theme.font(size: 10, weight: .semibold))
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
                try provider.definition.exported().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func delete() {
        do {
            try value(of: monitor.providers.remove(id: provider.id))
        } catch {
            self.error = error.localizedDescription
            return
        }
        onDeleted()
    }
}
