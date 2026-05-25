import SwiftUI
import Domain
import Infrastructure

/// Ollama provider configuration card for `SettingsContentView`.
///
/// Lets the user pick a probe mode (API or Web), paste an API key,
/// override the env var name consulted for the key, test the connection,
/// and remove a saved key.
struct OllamaConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var ollamaConfigExpanded: Bool = false
    @State private var ollamaProbeMode: OllamaProbeMode = .api
    @State private var ollamaApiKeyInput: String = ""
    @State private var ollamaAuthEnvVarInput: String = ""
    @State private var showOllamaApiKey: Bool = false
    @State private var isTestingOllama: Bool = false
    @State private var ollamaTestResult: String?

    var body: some View {
        DisclosureGroup(isExpanded: $ollamaConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            ollamaConfigForm
        } label: {
            ollamaConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        ollamaConfigExpanded.toggle()
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
            ollamaProbeMode = settings.ollama.ollamaProbeMode()
            ollamaAuthEnvVarInput = settings.ollama.ollamaAuthEnvVar()
        }
    }

    // MARK: - Header

    private var ollamaConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.36, blue: 0.40),
                                Color(red: 0.20, green: 0.20, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Ollama Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Ollama Cloud / Pro quota tracking")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    // MARK: - Form

    private var ollamaConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            probeModePicker
            modeDescriptions
            apiKeyField
            envVarField
            lookupOrder
            testButton

            if let result = ollamaTestResult {
                Text(result)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(result.contains("Success") ? theme.statusHealthy : theme.statusCritical)
            }

            helpLink
            deleteKeyButton
        }
    }

    private var probeModePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROBE MODE")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)

            Picker("", selection: $ollamaProbeMode) {
                ForEach(OllamaProbeMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: ollamaProbeMode) { _, newValue in
                settings.ollama.setOllamaProbeMode(newValue)
                Task {
                    await monitor.refresh(providerId: "ollama")
                }
            }
        }
    }

    private var modeDescriptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundStyle(ollamaProbeMode == .api ? theme.accentPrimary : theme.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("API Mode")
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(ollamaProbeMode == .api ? theme.textPrimary : theme.textSecondary)

                    Text("Uses an Ollama API key (Bearer token). Most reliable.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(ollamaProbeMode == .web ? theme.accentPrimary : theme.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Web Mode")
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(ollamaProbeMode == .web ? theme.textPrimary : theme.textSecondary)

                    Text("Reads ollama.com session cookies from your browser.")
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("API KEY")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Spacer()

                if settings.ollama.hasOllamaApiKey() {
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
                    if showOllamaApiKey {
                        TextField("", text: $ollamaApiKeyInput, prompt: Text("sk-...").foregroundStyle(theme.textTertiary))
                    } else {
                        SecureField("", text: $ollamaApiKeyInput, prompt: Text("sk-...").foregroundStyle(theme.textTertiary))
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
                    showOllamaApiKey.toggle()
                } label: {
                    Image(systemName: showOllamaApiKey ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(theme.glassBackground))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var envVarField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API KEY ENV VAR (ALTERNATIVE)")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)

            TextField("", text: $ollamaAuthEnvVarInput, prompt: Text("OLLAMA_API_KEY").foregroundStyle(theme.textTertiary))
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
                .onChange(of: ollamaAuthEnvVarInput) { _, newValue in
                    settings.ollama.setOllamaAuthEnvVar(newValue)
                }
        }
    }

    private var lookupOrder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API KEY LOOKUP ORDER")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)

            Text("1. Custom env var above (if set)")
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
            Text("2. OLLAMA_API_KEY / OLLAMA_KEY environment variables")
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
            Text("3. API key entered above")
                .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)
        }
    }

    @ViewBuilder
    private var testButton: some View {
        if isTestingOllama {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Testing connection...")
                    .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
            }
        } else {
            Button {
                Task { await testOllamaConnection() }
            } label: {
                Text("Save & Test Connection")
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
        }
    }

    private var helpLink: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Get your API key from the Ollama dashboard")
                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textTertiary)

            Link(destination: URL(string: "https://ollama.com/settings/keys")!) {
                HStack(spacing: 3) {
                    Text("Open Ollama API Keys")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(theme.accentPrimary)
            }
        }
    }

    @ViewBuilder
    private var deleteKeyButton: some View {
        if settings.ollama.hasOllamaApiKey() {
            Button {
                settings.ollama.deleteOllamaApiKey()
                ollamaApiKeyInput = ""
                ollamaTestResult = nil
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

    // MARK: - Actions

    private func testOllamaConnection() async {
        isTestingOllama = true
        ollamaTestResult = nil

        settings.ollama.setOllamaAuthEnvVar(ollamaAuthEnvVarInput)
        if !ollamaApiKeyInput.isEmpty {
            AppLog.credentials.info("Saving Ollama API key for connection test")
            settings.ollama.saveOllamaApiKey(ollamaApiKeyInput)
            ollamaApiKeyInput = ""
        }

        AppLog.credentials.info("Testing Ollama connection via provider refresh")
        await monitor.refresh(providerId: "ollama")

        if let error = monitor.provider(for: "ollama")?.lastError {
            AppLog.credentials.error("Ollama connection test failed: \(error.localizedDescription)")
            ollamaTestResult = "Failed: \(error.localizedDescription)"
        } else {
            AppLog.credentials.info("Ollama connection test succeeded")
            ollamaTestResult = "Success: Connection verified"
        }

        isTestingOllama = false
    }
}
