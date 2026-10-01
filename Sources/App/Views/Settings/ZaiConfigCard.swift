import SwiftUI
import Domain
import Infrastructure

/// Z.ai / GLM provider configuration card for SettingsView.
struct ZaiConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var zaiConfigExpanded: Bool = false
    @State private var zaiConfigPathInput: String = ""
    @State private var glmAuthEnvVarInput: String = ""
    @State private var zaiApiKeyInput: String = ""
    @State private var showZaiApiKey: Bool = false
    @State private var hasStoredZaiApiKey: Bool = false
    @State private var zaiApiKeyMessage: String?

    var body: some View {
        DisclosureGroup(isExpanded: $zaiConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                // Explanation text
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOKEN LOOKUP ORDER")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Text("1. First uses the API key saved in ClaudeBar settings")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                    Text("2. Falls back to the token in the settings.json file")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                    Text("3. Falls back to the environment variable if not found in file")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                // API Key input
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("API KEY")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(theme.textSecondary)
                            .tracking(0.5)

                        Spacer()

                        if hasStoredZaiApiKey {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Configured")
                                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                            }
                            .foregroundStyle(theme.statusHealthy)
                        }
                    }

                    HStack(spacing: 6) {
                        Group {
                            if showZaiApiKey {
                                TextField("", text: $zaiApiKeyInput, prompt: Text("glm-...").foregroundStyle(theme.textTertiary))
                            } else {
                                SecureField("", text: $zaiApiKeyInput, prompt: Text("glm-...").foregroundStyle(theme.textTertiary))
                            }
                        }
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )

                        Button {
                            showZaiApiKey.toggle()
                        } label: {
                            Image(systemName: showZaiApiKey ? "eye.slash.fill" : "eye.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(theme.glassBackground)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        saveZaiApiKey()
                    } label: {
                        Text("Save API Key")
                            .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.accentPrimary)
                            )
                    }
                    .buttonStyle(.plain)

                    if let message = zaiApiKeyMessage {
                        Text(message)
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                            .foregroundStyle(message.contains("Saved") ? theme.statusHealthy : theme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("SETTINGS.JSON PATH")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $zaiConfigPathInput, prompt: Text("~/.claude/settings.json").foregroundStyle(theme.textTertiary))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                        .onChange(of: zaiConfigPathInput) { _, newValue in
                            settings.zai.setZaiConfigPath(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("AUTH TOKEN ENV VAR (FALLBACK)")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    TextField("", text: $glmAuthEnvVarInput, prompt: Text("GLM_AUTH_TOKEN").foregroundStyle(theme.textTertiary))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: 1)
                                )
                        )
                        .onChange(of: glmAuthEnvVarInput) { _, newValue in
                            settings.zai.setGlmAuthEnvVar(newValue)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave both empty to use default path with no env var fallback")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }

                // Delete API key
                if hasStoredZaiApiKey {
                    Button {
                        settings.zai.deleteZaiApiKey()
                        hasStoredZaiApiKey = false
                        zaiApiKeyInput = ""
                        zaiApiKeyMessage = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 9))
                            Text("Remove API Key")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundStyle(theme.statusCritical)
                    }
                    .buttonStyle(.plain)
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.2, green: 0.6, blue: 0.9),
                                    Color(red: 0.15, green: 0.45, blue: 0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Z.ai / GLM Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Authentication fallback settings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

                Spacer()
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    zaiConfigExpanded.toggle()
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
        .onAppear {
            zaiConfigPathInput = settings.zai.zaiConfigPath()
            glmAuthEnvVarInput = settings.zai.glmAuthEnvVar()
            hasStoredZaiApiKey = settings.zai.hasZaiApiKey()
        }
    }

    // MARK: - Actions

    private func saveZaiApiKey() {
        let apiKey = zaiApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            zaiApiKeyMessage = "Enter an API key first"
            return
        }

        AppLog.credentials.info("Saving Z.ai API key from settings")
        settings.zai.saveZaiApiKey(apiKey)
        hasStoredZaiApiKey = true
        zaiApiKeyInput = ""
        zaiApiKeyMessage = "Saved: API key stored in ClaudeBar settings"
    }
}
