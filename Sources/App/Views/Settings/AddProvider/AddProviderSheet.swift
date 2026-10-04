import AppKit
import SwiftUI
import DataSources
import Domain
import Infrastructure
import Providers

/// *Add Provider* — USER_JOURNEYS moments 5–9. Four steps build a
/// `ProviderDraft`: *Start from*, *Connect* (with *Test Connection*), *Map
/// fields* (click what came back, watch the live card), *Look*. *Save* writes
/// the definition to the catalog, the key to the vault, and adds the provider
/// to the lineup — no restart.
struct AddProviderSheet: View {
    let monitor: QuotaMonitor
    let onDone: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private enum Step: Int, CaseIterable {
        case start, connect, map, look

        var title: String {
            switch self {
            case .start: "Start from"
            case .connect: "Connect"
            case .map: "Map fields"
            case .look: "Look"
            }
        }
    }

    private enum Origin: String, CaseIterable, Identifiable {
        case api = "API", cli = "CLI", file = "File", copy = "Copy a provider"
        var id: String { rawValue }
    }

    private enum KeyChoice: String, CaseIterable, Identifiable {
        case apiKey = "API key", environment = "Environment variable", none = "No key"
        var id: String { rawValue }
    }

    private enum MeasureChoice: String, CaseIterable, Identifiable {
        case percentUsed = "% used", percentLeft = "% left", money = "Money"
        var id: String { rawValue }
    }

    @State private var step: Step = .start
    @State private var origin: Origin = .api
    @State private var draft = ProviderDraft(start: .api)
    @State private var copySourceId: String?

    // Connect
    @State private var keyChoice: KeyChoice = .apiKey
    @State private var apiKey = ""
    @State private var environmentVariable = ""
    @State private var sendsBearer = true
    @State private var headerName = "X-API-Key"
    @State private var response: Response?
    @State private var testText: String?
    @State private var testFailed = false
    @State private var isTesting = false

    // Map fields
    @State private var measure: MeasureChoice = .percentUsed
    @State private var currency = "USD"
    @State private var isBalance = false

    // Look
    @State private var color = Color.accentColor
    @State private var colorChanged = false
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case .start: startStep
                    case .connect: connectStep
                    case .map: mapStep
                    case .look: lookStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 560, height: 560)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Provider")
                .font(.system(size: 17, weight: .bold, design: theme.fontDesign))
            HStack(spacing: 6) {
                ForEach(visibleSteps, id: \.self) { item in
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold, design: theme.fontDesign))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(item == step ? theme.accentPrimary.opacity(0.25) : theme.glassBorder.opacity(0.4)))
                }
            }
        }
    }

    /// A copy keeps its connection and mapping: it goes straight to *Look*.
    private var visibleSteps: [Step] {
        origin == .copy ? [.start, .look] : Step.allCases
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onDone)
            Spacer()
            if step != .start {
                Button("Back") { move(by: -1) }
            }
            if step == .look {
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Button("Next") { move(by: 1) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            }
        }
    }

    private func move(by offset: Int) {
        let steps = visibleSteps
        guard let index = steps.firstIndex(of: step) else { return }
        let next = min(max(index + offset, 0), steps.count - 1)
        if step == .start, offset > 0 { applyOrigin() }
        step = steps[next]
    }

    private var canAdvance: Bool {
        switch step {
        case .start: origin != .copy || copySourceId != nil
        case .connect: response != nil
        case .map: (try? previewDefinition()) != nil
        case .look: true
        }
    }

    // MARK: - Start from

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("START FROM")
            Picker("", selection: $origin) {
                ForEach(Origin.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            switch origin {
            case .api: hint("Ask a URL for usage, with a key you give it.")
            case .cli: hint("Run a command that prints usage — as text or JSON. It runs with your rights.")
            case .file: hint("Read a file some tool keeps up to date.")
            case .copy:
                Picker("Provider", selection: $copySourceId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(copyableDefinitions, id: \.id) { definition in
                        Text(definition.profile.name).tag(Optional(definition.id))
                    }
                }
                hint("The copy fetches and maps the same way, under its own name, as a Custom provider.")
            }
        }
    }

    private var copyableDefinitions: [ProviderDefinition] {
        (Array(Providers.builtInDefinitions.values) + ProviderCatalog().custom())
            .sorted { $0.profile.name < $1.profile.name }
    }

    private func applyOrigin() {
        let start: ProviderDraft.Start = switch origin {
        case .api: .api
        case .cli: .cli
        case .file: .file
        case .copy: copyableDefinitions.first { $0.id == copySourceId }.map(ProviderDraft.Start.copy) ?? .api
        }
        guard draft.start != start else { return }
        var fresh = ProviderDraft(start: start)
        if case .copy = start { fresh.name = "\(fresh.name) copy" }
        draft = fresh
        response = nil
        testText = nil
    }

    // MARK: - Connect

    @ViewBuilder
    private var connectStep: some View {
        switch draft.start {
        case .api:
            label("URL")
            TextField("https://", text: $draft.url)
                .textFieldStyle(.roundedBorder)

            label("KEY LOOKUP ORDER")
            Picker("", selection: $keyChoice) {
                ForEach(KeyChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch keyChoice {
            case .apiKey:
                SecureField("Paste the key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                hint("Kept in your Keychain — never in a file, and never exported.")
            case .environment:
                TextField("VARIABLE_NAME", text: $environmentVariable)
                    .textFieldStyle(.roundedBorder)
                hint("Read when ClaudeBar starts; a variable set only in your shell profile isn't visible to it.")
            case .none:
                EmptyView()
            }

            if keyChoice != .none {
                label("SENT AS")
                Picker("", selection: $sendsBearer) {
                    Text("Authorization: Bearer").tag(true)
                    Text("Header").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !sendsBearer {
                    TextField("Header name", text: $headerName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        case .cli:
            label("COMMAND")
            TextField("tool usage --json", text: $draft.command)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            hint("ClaudeBar runs this in its own folder, with your rights, each time it refreshes.")
        case .file:
            label("FILE")
            HStack {
                TextField("~/.tool/usage.json", text: $draft.path)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…", action: chooseFile)
            }
        case .copy:
            EmptyView()
        }

        HStack(spacing: 8) {
            Button(isTesting ? "Testing…" : "Test Connection", action: testConnection)
                .disabled(isTesting)
            if let testText {
                Text(testText)
                    .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(testFailed ? theme.statusWarning : theme.statusHealthy)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)

        if let response {
            label("RESPONSE")
            Text(response.text.prefix(2_000))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.glassBackground))
        }
    }

    private func applyConnection() {
        guard case .api = draft.start else { return }
        draft.key = switch keyChoice {
        case .apiKey: .apiKey
        case .environment: .environment(environmentVariable.trimmingCharacters(in: .whitespaces))
        case .none: nil
        }
        draft.sentAs = sendsBearer ? .bearer : .header(headerName.trimmingCharacters(in: .whitespaces))
    }

    private func testConnection() {
        applyConnection()
        isTesting = true
        testText = nil
        Task {
            defer { isTesting = false }
            do {
                let source = DataSources.make(
                    try draft.connection(), providerId: "draft",
                    scripts: Providers.builtInScripts, secrets: TypedKey(value: apiKey)
                )
                let answer = try await source.fetchResponse()
                response = answer
                testFailed = false
                testText = DataSourceSectionText.testResult(.success(answer))
            } catch let failure as DataSourceError {
                response = nil
                testFailed = true
                testText = DataSourceSectionText.testResult(.failure(failure))
            } catch {
                response = nil
                testFailed = true
                testText = error.localizedDescription
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            draft.path = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
        }
    }

    // MARK: - Map fields

    @ViewBuilder
    private var mapStep: some View {
        let fields = response.map(ResponseFields.init) ?? ResponseFields(Response(body: Data()))

        label("WHAT THE NUMBERS MEAN")
        Picker("", selection: $measure) {
            ForEach(MeasureChoice.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: measure) { _, _ in applyMeasure() }

        if fields.isEmpty, let response {
            textMapping(lines: ResponseFields.lines(of: response))
        } else {
            switch measure {
            case .percentUsed:
                fieldPicker("Used", selection: $draft.used, fields: fields.filter(\.isNumber))
            case .percentLeft:
                fieldPicker("Remaining", selection: $draft.remaining, fields: fields.filter(\.isNumber))
            case .money:
                fieldPicker("Remaining", selection: $draft.remaining, fields: fields.filter(\.isNumber))
                Toggle("never — a balance (no limit)", isOn: $isBalance)
                    .onChange(of: isBalance) { _, balance in if balance { draft.limit = nil } }
                if !isBalance {
                    fieldPicker("Limit", selection: $draft.limit, fields: fields.filter(\.isNumber))
                }
                HStack {
                    Text("Currency").font(.system(size: 11, design: theme.fontDesign))
                    TextField("USD", text: $currency)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: currency) { _, _ in applyMeasure() }
                }
            }
            fieldPicker("Resets", selection: $draft.resets, fields: Array(fields), allowsNever: true)
                .onChange(of: draft.resets) { _, path in
                    let value = fields.first { $0.path == path }
                    draft.resetsFormat = value?.isNumber == true ? .epochSeconds : .iso8601
                }
        }

        TextField("Quota name", text: $draft.quotaName)
            .textFieldStyle(.roundedBorder)

        label("LIVE CARD")
        Text(livePreview)
            .font(.system(size: 13, weight: .semibold, design: theme.fontDesign))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.glassBackground))
    }

    private func textMapping(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            hint("Click the line that holds the percentage.")
            ForEach(lines.prefix(40), id: \.self) { line in
                Button {
                    draft.textLabel = Self.label(of: line)
                } label: {
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            TextField("Line label", text: Binding(get: { draft.textLabel ?? "" }, set: { draft.textLabel = $0 }))
                .textFieldStyle(.roundedBorder)
        }
    }

    /// What comes before a line's percentage: `"Quota: 42% left"` → `"Quota"`,
    /// `"5h limit = 80% left"` → `"5h limit"`.
    nonisolated static func label(of line: String) -> String {
        let percentage = line.range(of: #"[0-9]+(?:\.[0-9]+)?\s*%"#, options: .regularExpression)
        let prefix = percentage.map { line[..<$0.lowerBound] } ?? line[...]
        return prefix.trimmingCharacters(in: CharacterSet(charactersIn: " :=-\t"))
    }

    private func fieldPicker(_ title: String, selection: Binding<String?>, fields: [ResponseFields.Field], allowsNever: Bool = false) -> some View {
        Picker(title, selection: selection) {
            Text(allowsNever ? "never" : "Choose…").tag(String?.none)
            ForEach(fields, id: \.path) { field in
                Text("\(field.path)  \(field.value.prefix(30))").tag(Optional(field.path))
            }
        }
    }

    private func applyMeasure() {
        draft.measure = switch measure {
        case .percentUsed: .percentUsed
        case .percentLeft: .percentLeft
        case .money: .money(currency: currency.trimmingCharacters(in: .whitespaces).uppercased())
        }
    }

    private func previewDefinition() throws -> ProviderDefinition {
        var preview = draft
        if preview.name.trimmingCharacters(in: .whitespaces).isEmpty { preview.name = "Preview" }
        return try preview.definition(id: "draft")
    }

    private var livePreview: String {
        guard let response else { return "Test the connection first." }
        do {
            let definition = try previewDefinition()
            let usage = try DataSources.make(definition.dataSources[0], providerId: "draft").read(response)
            guard let quota = usage.quotas.first else { return "No numbers found yet." }
            return QuotaPreview.text(quota)
        } catch let missing as ProviderDraft.Missing {
            return missing.localizedDescription
        } catch let failure as DataSourceError {
            return "\(RefreshReport.headline(for: failure.step)) · \(failure.reason.localizedDescription)"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Look

    @ViewBuilder
    private var lookStep: some View {
        label("NAME")
        TextField("OpenRouter", text: $draft.name)
            .textFieldStyle(.roundedBorder)

        label("SYMBOL · COLOUR")
        HStack(spacing: 10) {
            Image(systemName: draft.symbol ?? baseLook?.symbol ?? "gauge.with.dots.needle.33percent")
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 28)
            TextField(baseLook?.symbol ?? "SF Symbol", text: Binding(get: { draft.symbol ?? "" }, set: { draft.symbol = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            // Only the person picking a colour changes it — showing the
            // copied provider's colour is not a change.
            ColorPicker("", selection: Binding(get: { color }, set: { color = $0; colorChanged = true }), supportsOpacity: false)
                .labelsHidden()
        }
        .onAppear {
            if !colorChanged, let base = baseLook?.color { color = base.color(for: colorScheme) }
        }

        label("DASHBOARD (OPTIONAL)")
        TextField("https://", text: $draft.dashboard)
            .textFieldStyle(.roundedBorder)

        if needsKeyForCopy {
            label("API KEY")
            SecureField("Paste the key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
        }

        if let saveError {
            Text(saveError)
                .font(.system(size: 11, weight: .semibold, design: theme.fontDesign))
                .foregroundStyle(theme.statusWarning)
        }
    }

    /// The look a copy keeps unless the person changes it.
    private var baseLook: ProviderLook? {
        guard case .copy(let source) = draft.start else { return nil }
        return source.profile.look
    }

    /// A copy of a provider whose key the person gave ClaudeBar needs that key
    /// again — keys are never copied.
    private var needsKeyForCopy: Bool {
        guard case .copy(let source) = draft.start else { return false }
        return !source.neededSettings.isEmpty
    }

    // MARK: - Save

    private func save() {
        applyConnection()
        if origin != .copy || colorChanged {
            draft.color = Self.shades(of: color)
        }
        do {
            let catalog = ProviderCatalog()
            let definition = try draft.definition(id: catalog.mintId(for: draft.name))
            try catalog.add(definition)
            let vault = ProviderVault()
            if !apiKey.isEmpty, draft.key == .apiKey || needsKeyForCopy {
                vault.save(apiKey, "apiKey", provider: definition.id)
            }
            Providers.register(custom: definition)
            let provider = Providers.make(definition, settings: JSONSettingsRepository.shared, secrets: vault)
            monitor.addProvider(provider.defaultAccount)
            Task { await monitor.refresh(providerId: provider.defaultAccount.id) }
            onDone()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func shades(of color: Color) -> ProviderLook.Shades? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let value = ProviderLook.RGB(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        return ProviderLook.Shades(light: value, dark: value)
    }

    // MARK: - Words

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
            .foregroundStyle(theme.textSecondary)
            .tracking(0.5)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The key typed in *Connect*, for *Test Connection* before anything is saved.
private struct TypedKey: SecretStore {
    let value: String

    func secret(_ name: String, provider: String) -> String? {
        value.isEmpty ? nil : value
    }
}
