import SwiftUI
import Domain
import Infrastructure

/// Vercel AI Gateway provider configuration card for SettingsView.
struct VercelConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var vercelConfigExpanded: Bool = false
    @State private var vercelApiKeyInput: String = ""
    @State private var vercelAuthEnvVarInput: String = ""
    @State private var showVercelApiKey: Bool = false
    @State private var hasStoredVercelApiKey: Bool = false
    @State private var isTestingVercel = false
    @State private var vercelTestResult: String?

    var body: some View {
        DisclosureGroup(isExpanded: $vercelConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            vercelConfigForm
        } label: {
            vercelConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        vercelConfigExpanded.toggle()
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
            vercelAuthEnvVarInput = settings.vercel.vercelAuthEnvVar()
            hasStoredVercelApiKey = settings.vercel.hasVercelApiKey()
        }
    }

    private var vercelConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.25),
                                Color(white: 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: "triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Vercel Gateway Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("AI Gateway credits balance")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var vercelConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // API Key input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API KEY")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer()

                    if hasStoredVercelApiKey {
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
                        if showVercelApiKey {
                            TextField("", text: $vercelApiKeyInput, prompt: Text("vck_...").foregroundStyle(theme.textTertiary))
                        } else {
                            SecureField("", text: $vercelApiKeyInput, prompt: Text("vck_...").foregroundStyle(theme.textTertiary))
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
                        showVercelApiKey.toggle()
                    } label: {
                        Image(systemName: showVercelApiKey ? "eye.slash.fill" : "eye.fill")
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
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                TextField("", text: $vercelAuthEnvVarInput, prompt: Text("AI_GATEWAY_API_KEY").foregroundStyle(theme.textTertiary))
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
                    .onChange(of: vercelAuthEnvVarInput) { _, newValue in
                        settings.vercel.setVercelAuthEnvVar(newValue)
                    }
            }

            // Token lookup order
            VStack(alignment: .leading, spacing: 4) {
                Text("API KEY LOOKUP ORDER")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                Text("1. First checks environment variable (default: AI_GATEWAY_API_KEY)")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
                Text("2. Falls back to API key entered above")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            // Save & Test button
            if isTestingVercel {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Testing connection...")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Button {
                    Task {
                        await testVercelConnection()
                    }
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

            if let result = vercelTestResult {
                Text(result)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(result.contains("Success") ? theme.statusHealthy : theme.statusCritical)
            }

            // Help link
            VStack(alignment: .leading, spacing: 4) {
                Text("Get your API key from the Vercel AI Gateway dashboard")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Link(destination: URL(string: "https://vercel.com/dashboard/ai-gateway")!) {
                    HStack(spacing: 3) {
                        Text("Open Vercel AI Gateway")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
            }

            // Delete API key
            if hasStoredVercelApiKey {
                Button {
                    if settings.vercel.deleteVercelApiKey() {
                        hasStoredVercelApiKey = false
                        vercelApiKeyInput = ""
                        vercelTestResult = nil
                    } else {
                        hasStoredVercelApiKey = settings.vercel.hasVercelApiKey()
                        vercelTestResult = "Failed to remove API key from Keychain"
                    }
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
    }

    // MARK: - Actions

    private func testVercelConnection() async {
        isTestingVercel = true
        vercelTestResult = nil
        defer { isTestingVercel = false }

        settings.vercel.setVercelAuthEnvVar(vercelAuthEnvVarInput)
        let apiKey = vercelApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            AppLog.credentials.info("Saving Vercel API key for connection test")
            settings.vercel.saveVercelApiKey(apiKey)
            hasStoredVercelApiKey = true
            vercelApiKeyInput = ""
        }

        guard let provider = monitor.provider(for: "vercel-gateway") else {
            vercelTestResult = "Failed: Vercel provider is not registered"
            return
        }

        guard await provider.isAvailable() else {
            vercelTestResult = "Failed: No API key found"
            return
        }

        AppLog.credentials.info("Testing Vercel connection via provider refresh")
        do {
            _ = try await provider.refresh()
            AppLog.credentials.info("Vercel connection test succeeded")
            vercelTestResult = "Success: Connection verified"
        } catch ProbeError.authenticationRequired {
            let message = "Vercel rejected the API key. New keys may take a moment to activate."
            AppLog.credentials.error("Vercel connection test failed: \(message)")
            vercelTestResult = "Failed: \(message)"
        } catch {
            AppLog.credentials.error("Vercel connection test failed: \(error.localizedDescription)")
            vercelTestResult = "Failed: \(error.localizedDescription)"
        }
    }
}
