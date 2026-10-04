import SwiftUI
import AppKit
import DataSources
import Domain
import Providers

/// Settings' *Data source* section for any provider that is data (#352):
/// the data sources to pick from, where the key is looked for, the fallback
/// as a sentence, and *Test Connection* — all read from the definition, so a
/// provider needs no card of its own. Replaces the PROBE MODE cards.
struct DataSourceSection: View {
    let provider: Provider
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var expanded = false
    @State private var kind = ""
    @State private var fallbackOn = true
    @State private var testResult: String?
    @State private var testFailed = false
    @State private var isTesting = false
    @State private var cliPath = ""
    @State private var cliPathError: String?

    private var text: DataSourceSectionText { DataSourceSectionText(definition: provider.definitionAsRun) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            form
        } label: {
            header
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
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
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            kind = provider.activeKind
            fallbackOn = provider.isFallbackEnabled(from: kind)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ProviderIconView(providerId: provider.id, size: 28, showGlow: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text(text.subtitle)
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            Text(text.origin.uppercased())
                .font(.system(size: 8, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(theme.glassBorder.opacity(0.6)))
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("DATA SOURCE")

                Picker("", selection: $kind) {
                    ForEach(text.choices, id: \.kind) { choice in
                        Text(choice.label).tag(choice.kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, newValue in
                    pick(newValue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(text.choices, id: \.kind) { choice in
                    choiceRow(choice)
                }
            }

            if let note = text.note(for: kind) {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
            }

            if let cacheNote = text.cacheNote(for: kind) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 16)
                    Text(cacheNote)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            if let lookupOrder = text.lookupOrder(for: kind) {
                keyLookup(lookupOrder)
            }

            if let fallback = text.fallback(for: kind) {
                fallbackRow(fallback)
            }

            if let location = text.cliLocation {
                cliLocationRow(location)
            }

            testConnection
        }
        // Fill the card, aligned with its header — a disclosure group centres
        // content that is narrower than itself.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// *CLI LOCATION* — saved when the person presses Return or picks a file.
    private func cliLocationRow(_ location: (placeholder: String, help: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("CLI LOCATION")
            HStack(spacing: 6) {
                TextField(location.placeholder, text: $cliPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                    .onSubmit { saveCLIPath() }
                Button("Choose…") { chooseCLI() }
                    .controlSize(.small)
                if provider.cliPath != nil {
                    Button("Reset") { cliPath = ""; saveCLIPath() }
                        .controlSize(.small)
                }
            }
            Text(cliPathError ?? location.help)
                .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(cliPathError == nil ? theme.textTertiary : theme.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { cliPath = provider.cliPath ?? "" }
    }

    private func saveCLIPath() {
        do {
            try provider.setCLIPath(cliPath)
            cliPathError = nil
            cliPath = provider.cliPath ?? ""
        } catch {
            cliPathError = error.localizedDescription
        }
    }

    private func chooseCLI() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Use"
        panel.message = "Choose the \(provider.definition.cli ?? provider.name) program."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            cliPath = url.path
            saveCLIPath()
        }
    }

    private func choiceRow(_ choice: DataSourceSectionText.Choice) -> some View {
        let picked = choice.kind == kind
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(picked ? theme.accentPrimary : theme.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(picked ? theme.textPrimary : theme.textSecondary)

                if let summary = choice.summary {
                    Text(summary)
                        .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    private func keyLookup(_ order: String) -> some View {
        let found = provider.hasKey(for: kind)
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("KEY LOOKUP ORDER")

            Text(order)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(found ? theme.statusHealthy : theme.statusWarning)

                Text(found ? "Key found" : "No key found")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(found ? theme.statusHealthy : theme.statusWarning)
            }

            if !found, let hint = text.keyHint(for: kind) {
                Text(hint)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func fallbackRow(_ sentence: String) -> some View {
        if text.fallbackIsSwitchable(for: kind) {
            HStack(spacing: 8) {
                Text(sentence)
                    .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                SettingsSwitch(isOn: $fallbackOn)
                    .accessibilityLabel(sentence)
            }
            .onChange(of: fallbackOn) { _, newValue in
                provider.setFallbackEnabled(newValue, from: kind)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 16)
                Text(sentence)
                    .font(.system(size: 9, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var testConnection: some View {
        HStack(spacing: 8) {
            Button(isTesting ? "Testing…" : "Test Connection") {
                isTesting = true
                testResult = nil
                Task {
                    let result = await provider.testConnection()
                    testResult = DataSourceSectionText.testResult(result)
                    if case .failure = result { testFailed = true } else { testFailed = false }
                    isTesting = false
                }
            }
            .disabled(isTesting)

            if let testResult {
                Text(testResult)
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(testFailed ? theme.statusWarning : theme.statusHealthy)
                    .lineLimit(2)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(theme.textSecondary)
            .tracking(0.5)
    }

    // MARK: - Picking

    /// Saves the choice for every login. A cached data source caps the
    /// background interval at its TTL, leaving "Off" alone (#204). Refreshes
    /// only when the new source needs no explicit check first — picking is not
    /// intent to start a CLI that may open a login on its own (#216).
    private func pick(_ newKind: String) {
        guard provider.use(newKind) else { return }
        fallbackOn = provider.isFallbackEnabled(from: newKind)
        testResult = nil
        if let ttl = provider.definition.dataSource(newKind)?.cache?.ttl,
           let seconds = settings.refreshInterval.seconds, Double(seconds) < ttl {
            settings.refreshInterval = RefreshInterval.allCases
                .first { ($0.seconds).map { Double($0) >= ttl } ?? false } ?? settings.refreshInterval
        }
        guard provider.definition.dataSource(newKind)?.verifyBeforeBackground != true else { return }
        Task {
            for account in provider.accounts where account.isEnabled {
                await monitor.refresh(providerId: account.id)
            }
        }
    }
}
