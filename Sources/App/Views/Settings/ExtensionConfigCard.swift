import SwiftUI
import Domain
import Infrastructure

/// Dynamic settings card for extension providers.
/// Auto-generates form fields from the extension manifest's config declarations.
/// Bindings read/write the repository directly — no @State cache.
struct ExtensionConfigCard: View {
    let provider: ExtensionProvider
    let configRepository: any ExtensionConfigRepository

    @Environment(\.appTheme) private var theme
    @State private var configExpanded: Bool = false
    @State private var secretVisible: [String: Bool] = [:]

    private var manifest: ExtensionManifest { provider.manifest }
    private var extensionId: String { manifest.id }

    var body: some View {
        DisclosureGroup(isExpanded: $configExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(manifest.configFields, id: \.id) { field in
                    fieldView(for: field)
                }
            }
        } label: {
            headerView
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        configExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconGradient)
                    .frame(width: 32, height: 32)

                Image(systemName: manifest.icon ?? "puzzlepiece.extension.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(manifest.name) Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Text(manifest.description ?? "Extension settings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()
        }
    }

    // MARK: - Field Rendering

    @ViewBuilder
    private func fieldView(for field: ConfigField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundColor(theme.textSecondary)

            switch field.type {
            case .string, .number, .path:
                textFieldView(for: field)
            case .secret:
                secretFieldView(for: field)
            case .toggle:
                toggleView(for: field)
            case .choice:
                pickerView(for: field)
            }

            if let helpText = field.helpText {
                Text(helpText)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }
        }
    }

    private func textFieldView(for field: ConfigField) -> some View {
        TextField(
            "",
            text: binding(for: field),
            prompt: Text(field.placeholder ?? "").foregroundColor(theme.textTertiary)
        )
        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
        .foregroundColor(theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(inputBackground)
    }

    private func secretFieldView(for field: ConfigField) -> some View {
        HStack(spacing: 8) {
            Group {
                if secretVisible[field.id] == true {
                    TextField(
                        "",
                        text: binding(for: field),
                        prompt: Text(field.placeholder ?? "").foregroundColor(theme.textTertiary)
                    )
                } else {
                    SecureField(
                        "",
                        text: binding(for: field),
                        prompt: Text(field.placeholder ?? "").foregroundColor(theme.textTertiary)
                    )
                }
            }
            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
            .foregroundColor(theme.textPrimary)

            Button {
                secretVisible[field.id] = !(secretVisible[field.id] ?? false)
            } label: {
                Image(systemName: secretVisible[field.id] == true ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(inputBackground)
    }

    private func toggleView(for field: ConfigField) -> some View {
        Toggle(isOn: Binding(
            get: {
                readValue(for: field) == "true"
            },
            set: { newValue in
                writeValue(newValue ? "true" : "false", for: field)
            }
        )) {
            EmptyView()
        }
        .toggleStyle(.switch)
        .tint(theme.accentPrimary)
    }

    private func pickerView(for field: ConfigField) -> some View {
        Picker("", selection: binding(for: field)) {
            ForEach(field.options ?? [], id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Helpers

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.glassBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.glassBorder, lineWidth: 1)
            )
    }

    private var iconGradient: LinearGradient {
        if let primary = manifest.colors?.primary, let color = Color(hex: primary) {
            return LinearGradient(
                colors: [color, color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [theme.accentPrimary, theme.accentPrimary.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Binding that reads/writes the repository directly. No @State cache.
    private func binding(for field: ConfigField) -> Binding<String> {
        Binding(
            get: { readValue(for: field) },
            set: { newValue in writeValue(newValue, for: field) }
        )
    }

    private func readValue(for field: ConfigField) -> String {
        if field.isSecret {
            return configRepository.secretValue(forFieldId: field.id, extensionId: extensionId) ?? field.defaultValue ?? ""
        }
        return configRepository.value(forFieldId: field.id, extensionId: extensionId) ?? field.defaultValue ?? ""
    }

    private func writeValue(_ value: String, for field: ConfigField) {
        let storedValue = value.isEmpty ? nil : value
        if field.isSecret {
            configRepository.setSecretValue(storedValue, forFieldId: field.id, extensionId: extensionId)
        } else {
            configRepository.setValue(storedValue, forFieldId: field.id, extensionId: extensionId)
        }
    }
}
