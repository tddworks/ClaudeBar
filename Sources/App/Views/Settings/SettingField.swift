import SwiftUI
import Providers

/// One `Setting`, drawn by its kind — a picker for a choice, a secure field
/// for a secret, a text field otherwise, with the default as its placeholder.
/// *Add Account* and a provider's settings section both draw it.
struct SettingField: View {
    let setting: Setting
    @Binding var value: String
    /// What an empty secret field says — *Saved in Keychain* once a key is kept.
    var secretPlaceholder: String?
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(setting.label).font(.callout).foregroundStyle(theme.textSecondary)
            switch setting.kind {
            case .choice(let options):
                Picker(setting.label, selection: $value) {
                    ForEach(options) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
            case .secret:
                SecureField(secretPlaceholder ?? setting.label, text: $value)
                    .textFieldStyle(.roundedBorder)
            case .text, .path:
                TextField(setting.default ?? setting.label, text: $value)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
