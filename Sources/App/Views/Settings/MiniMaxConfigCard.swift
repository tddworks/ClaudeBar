import SwiftUI
import Domain
import Infrastructure

/// MiniMax provider configuration card for SettingsView.
struct MiniMaxConfigCard: View {
    @ObservedObject var monitor: QuotaMonitor

    @ObservedObject var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var miniMaxConfigExpanded: Bool = false
    @State private var miniMaxApiKeyInput: String = ""
    @State private var miniMaxAuthEnvVarInput: String = ""
    @State private var miniMaxRegion: MiniMaxRegion = .china
    @State private var showMiniMaxApiKey: Bool = false
    @State private var isTestingMiniMax = false
    @State private var miniMaxTestResult: String?

    var body: some View {
        DisclosureGroup(isExpanded: $miniMaxConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            miniMaxConfigForm
        } label: {
            miniMaxConfigHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        miniMaxConfigExpanded.toggle()
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
            miniMaxRegion = settings.minimax.minimaxRegion()
            miniMaxAuthEnvVarInput = settings.minimax.minimaxAuthEnvVar()
        }
    }

    private var miniMaxConfigHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.91, green: 0.27, blue: 0.42),
                                Color(red: 0.96, green: 0.53, blue: 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MiniMax Configuration")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)

                Text("Coding Plan quota tracking")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var miniMaxConfigForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Region selector
            VStack(alignment: .leading, spacing: 6) {
                Text("REGION")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textSecondary)

                Picker("", selection: $miniMaxRegion) {
                    ForEach(MiniMaxRegion.allCases, id: \.self) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: miniMaxRegion) { newValue in
                    settings.minimax.setMinimaxRegion(newValue)
                    Task {
                        await monitor.refresh(providerId: "minimax")
                    }
                }
            }

            // API Key input
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API KEY")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)

                    Spacer()

                    if settings.minimax.hasMinimaxApiKey() {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("Configured")
                                .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        }
                        .foregroundColor(theme.statusHealthy)
                    }
                }

                HStack(spacing: 6) {
                    Group {
                        if showMiniMaxApiKey {
                            TextField("", text: $miniMaxApiKeyInput, prompt: Text("eyJhbGci...").foregroundColor(theme.textTertiary))
                        } else {
                            SecureField("", text: $miniMaxApiKeyInput, prompt: Text("eyJhbGci...").foregroundColor(theme.textTertiary))
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)
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
                        showMiniMaxApiKey.toggle()
                    } label: {
                        Image(systemName: showMiniMaxApiKey ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textSecondary)
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
                    .foregroundColor(theme.textSecondary)

                TextField("", text: $miniMaxAuthEnvVarInput, prompt: Text("MINIMAX_API_KEY").foregroundColor(theme.textTertiary))
                    .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textPrimary)
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
                    .onChange(of: miniMaxAuthEnvVarInput) { newValue in
                        settings.minimax.setMinimaxAuthEnvVar(newValue)
                    }
            }

            // Token lookup order
            VStack(alignment: .leading, spacing: 4) {
                Text("API KEY LOOKUP ORDER")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textSecondary)

                Text("1. First checks environment variable (default: MINIMAX_API_KEY)")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
                Text("2. Falls back to API key entered above")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)
            }

            // Save & Test button
            if isTestingMiniMax {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Testing connection...")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)
                }
            } else {
                Button {
                    Task {
                        await testMiniMaxConnection()
                    }
                } label: {
                    Text("Save & Test Connection")
                        .font(.system(size: 11, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.accentPrimary)
                        )
                }
                .buttonStyle(.plain)
            }

            if let result = miniMaxTestResult {
                Text(result)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(result.contains("Success") ? theme.statusHealthy : theme.statusCritical)
            }

            // Help link
            VStack(alignment: .leading, spacing: 4) {
                Text("Get your API key from MiniMax platform")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundColor(theme.textTertiary)

                Link(destination: miniMaxRegion.apiKeysURL) {
                    HStack(spacing: 3) {
                        Text("Open MiniMax API Keys")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundColor(theme.accentPrimary)
                }
            }

            // Delete API key
            if settings.minimax.hasMinimaxApiKey() {
                Button {
                    settings.minimax.deleteMinimaxApiKey()
                    miniMaxApiKeyInput = ""
                    miniMaxTestResult = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 9))
                        Text("Remove API Key")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    }
                    .foregroundColor(theme.statusCritical)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func testMiniMaxConnection() async {
        isTestingMiniMax = true
        miniMaxTestResult = nil

        settings.minimax.setMinimaxAuthEnvVar(miniMaxAuthEnvVarInput)
        if !miniMaxApiKeyInput.isEmpty {
            AppLog.credentials.info("Saving MiniMax API key for connection test")
            settings.minimax.saveMinimaxApiKey(miniMaxApiKeyInput)
            miniMaxApiKeyInput = ""
        }

        AppLog.credentials.info("Testing MiniMax connection via provider refresh")
        await monitor.refresh(providerId: "minimax")

        if let error = monitor.provider(for: "minimax")?.lastError {
            AppLog.credentials.error("MiniMax connection test failed: \(error.localizedDescription)")
            miniMaxTestResult = "Failed: \(error.localizedDescription)"
        } else {
            AppLog.credentials.info("MiniMax connection test succeeded")
            miniMaxTestResult = "Success: Connection verified"
        }

        isTestingMiniMax = false
    }
}
