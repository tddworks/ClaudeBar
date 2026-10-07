import SwiftUI
import Kit

/// DeepSeek provider configuration card for SettingsView.
/// Mirrors MiniMaxConfigCard (minus the region picker) — DeepSeek has a single global endpoint.
struct DeepSeekConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var deepSeekConfigExpanded: Bool = false
    @State private var deepSeekApiKeyInput: String = ""
    @State private var deepSeekAuthEnvVarInput: String = ""
    @State private var showDeepSeekApiKey: Bool = false
    @State private var hasStoredDeepSeekApiKey: Bool = false
    @State private var isTestingDeepSeek = false
    @State private var deepSeekTestResult: String?

    /// *API key environment variable* — the definition's `authEnvVar` setting.
    private func authEnvVar() -> String {
        guard let product = monitor.providers.provider(id: "deepseek"),
              let setting = product.definition.setting(id: "authEnvVar") else { return "" }
        return product.configuration.value(setting: setting, ownValues: [:]) ?? ""
    }

    private func setAuthEnvVar(_ name: String) {
        monitor.providers.provider(id: "deepseek")?.configuration.set(setting: "authEnvVar", value: name)
    }

    var body: some View {

        let _ = KitObservation.track()
        DisclosureGroup(isExpanded: $deepSeekConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            deepSeekConfigForm
        } label: {
            deepSeekConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        deepSeekConfigExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient).themeShadow(theme)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            deepSeekAuthEnvVarInput = authEnvVar()
            hasStoredDeepSeekApiKey = (Kit.shared.secret(name: "apiKey", providerId: "deepseek") != nil)
        }
    }

    private var deepSeekConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.52, blue: 1.0),
                                Color(red: 0.22, green: 0.28, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "d.square.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Default Account")
                    .font(theme.font(size: 14, weight: .bold))
                    .foregroundStyle(theme.textPrimary)

                Text("DeepSeek key and environment variable")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var deepSeekConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // API Key input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API KEY")
                        .font(theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer()

                    if hasStoredDeepSeekApiKey {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("Configured")
                                .font(theme.font(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(theme.statusHealthy)
                    }
                }

                HStack(spacing: 6) {
                    Group {
                        if showDeepSeekApiKey {
                            TextField("", text: $deepSeekApiKeyInput, prompt: Text("sk-...").foregroundStyle(theme.textTertiary))
                        } else {
                            SecureField("", text: $deepSeekApiKeyInput, prompt: Text("sk-...").foregroundStyle(theme.textTertiary))
                        }
                    }
                    .font(theme.font(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                            )
                    )

                    Button {
                        showDeepSeekApiKey.toggle()
                    } label: {
                        Image(systemName: showDeepSeekApiKey ? "eye.slash.fill" : "eye.fill")
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
            }

            // Environment Variable
            VStack(alignment: .leading, spacing: 6) {
                Text("API KEY ENV VAR (ALTERNATIVE)")
                    .font(theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                TextField("", text: $deepSeekAuthEnvVarInput, prompt: Text("DEEPSEEK_API_KEY").foregroundStyle(theme.textTertiary))
                    .font(theme.font(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(theme.glassBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                            )
                    )
                    .onChange(of: deepSeekAuthEnvVarInput) { _, newValue in
                        setAuthEnvVar(newValue)
                    }
            }

            // Token lookup order
            VStack(alignment: .leading, spacing: 4) {
                Text("API KEY LOOKUP ORDER")
                    .font(theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Text("1. First checks environment variable (default: DEEPSEEK_API_KEY)")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
                Text("2. Falls back to API key entered above")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }

            // Save & Test button
            if isTestingDeepSeek {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Testing connection...")
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Button {
                    Task {
                        await testDeepSeekConnection()
                    }
                } label: {
                    Text("Save & Test Connection")
                        .font(theme.font(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
            }

            if let result = deepSeekTestResult {
                Text(result)
                    .font(theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(result.contains("Success") ? theme.statusHealthy : theme.statusCritical)
            }

            // Help link
            VStack(alignment: .leading, spacing: 4) {
                Text("Get your API key from the DeepSeek platform")
                    .font(theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)

                Link(destination: URL(string: "https://platform.deepseek.com/api_keys")!) {
                    HStack(spacing: 3) {
                        Text("Open DeepSeek API Keys")
                            .font(theme.font(size: 9, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }

            // Delete API key
            if hasStoredDeepSeekApiKey {
                Button {
                    Kit.shared.deleteSecret(name: "apiKey", providerId: "deepseek")
                    hasStoredDeepSeekApiKey = (Kit.shared.secret(name: "apiKey", providerId: "deepseek") != nil)
                    deepSeekApiKeyInput = ""
                    deepSeekTestResult = hasStoredDeepSeekApiKey ? "Failed: ClaudeBar could not remove the API key securely." : nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9))
                        Text("Remove API Key")
                            .font(theme.font(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(theme.statusCritical)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func testDeepSeekConnection() async {
        isTestingDeepSeek = true
        deepSeekTestResult = nil
        defer { isTestingDeepSeek = false }

        setAuthEnvVar(deepSeekAuthEnvVarInput)
        let apiKey = deepSeekApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            AppLog.credentials.info("Saving DeepSeek API key for connection test")
            Kit.shared.saveSecret(value: apiKey, name: "apiKey", providerId: "deepseek")
            guard Kit.shared.secret(name: "apiKey", providerId: "deepseek") == apiKey else {
                deepSeekTestResult = "Failed: ClaudeBar could not save the API key securely."
                return
            }
            hasStoredDeepSeekApiKey = true
            deepSeekApiKeyInput = ""
        }

        guard let provider = monitor.providers.provider(id: "deepseek") else {
            deepSeekTestResult = "Failed: DeepSeek provider is not registered"
            return
        }

        guard await provider.canRefresh(provider.defaultAccount) else {
            deepSeekTestResult = "Failed: No API key found"
            return
        }

        AppLog.credentials.info("Testing DeepSeek connection via provider refresh")
        do {
            let outcome = try await provider.refresh(account: provider.defaultAccount, kind: .interactive)
            if let failed = outcome as? RefreshOutcome.Failed {
                let message = failed.error.tag == "authenticationRequired"
                    ? "DeepSeek rejected the API key. New keys may take a moment to activate."
                    : failed.error.localizedDescription
                AppLog.credentials.error("DeepSeek connection test failed: \(message)")
                deepSeekTestResult = "Failed: \(message)"
                return
            }
            AppLog.credentials.info("DeepSeek connection test succeeded")
            deepSeekTestResult = "Success: Connection verified"
        } catch {
            AppLog.credentials.error("DeepSeek connection test failed: \(error.localizedDescription)")
            deepSeekTestResult = "Failed: \(error.localizedDescription)"
        }
    }
}
