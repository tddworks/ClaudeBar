import SwiftUI
import Domain
import Providers

/// *REGION*, *API KEY*, *CLI DATA FOLDER* … — a provider's form, drawn from
/// its definition. Values here are the provider's, and the default login's;
/// an added login keeps the values *Add Account* gave it. Saving runs every
/// login with the new value from the next refresh.
struct ProviderSettingsSection: View {
    let provider: Provider
    @Environment(\.appTheme) private var theme
    @State private var entered: [String: String] = [:]
    @State private var problem: String?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(theme.textSecondary)
                Text("Settings").font(.headline).foregroundStyle(theme.textPrimary)
                Spacer()
            }
            ForEach(provider.definition.defaultLoginSettings) { setting in
                let kept = provider.hasSaved(setting, for: provider.defaultAccount)
                HStack(alignment: .bottom, spacing: 8) {
                    SettingField(setting: setting, value: Binding(
                        get: { entered[setting.id] ?? provider.value(of: setting, for: provider.defaultAccount) ?? "" },
                        set: { entered[setting.id] = $0; saved = false }
                    ), secretPlaceholder: kept ? "Saved in Keychain — type to replace" : nil)
                    if kept {
                        // Forgets what is saved: a key leaves the vault, a value goes back to its default.
                        Button("Clear") { clear(setting) }
                    }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(theme.statusCritical)
            }
            HStack {
                if saved { Text("Saved").font(.caption).foregroundStyle(theme.textSecondary) }
                Spacer()
                Button("Save") { save() }.disabled(entered.isEmpty)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: theme.cardCornerRadius).fill(theme.cardGradient).themeShadow(theme))
        .overlay(RoundedRectangle(cornerRadius: theme.cardCornerRadius).stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
    }

    private func clear(_ setting: Setting) {
        do {
            try provider.set(setting.id, to: nil)
            entered[setting.id] = nil
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func save() {
        do {
            for (id, value) in entered { try provider.set(id, to: value) }
            entered = [:]
            problem = nil
            saved = true
        } catch {
            problem = error.localizedDescription
        }
    }
}
