import AppKit
import SwiftUI
import Kit

/// Providers pane: master list of every registered provider with enable
/// toggles; selecting a row drills into that provider's configuration.
struct ProvidersPane: View {
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var selectedProviderId: String?
    @State private var addingProvider = false
    @State private var importing: IdentifiedReview?
    @State private var importError: String?
    /// The list's order, taken when it appears — enabled providers first (#141).
    @State private var listOrder: [String] = []

    var body: some View {

        let _ = KitObservation.track()
        if let productId = selectedProviderId,
           let tab = monitor.productTabs.first(where: { $0.id == productId }) {
            ProviderDetailView(monitor: monitor, tab: tab, provider: tab.page) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedProviderId = nil
                }
            }
        } else {
            providerList
        }
    }

    private var providerList: some View {
        SettingsPane(
            title: "Providers",
            subtitle: "Enable the assistants you use and order them — the menu bar follows this order (⌘1–⌘9 included). Click a provider to configure it."
        ) {
            VStack(spacing: 8) {
                ForEach(Array(listedProducts.enumerated()), id: \.element.id) { index, tab in
                    ProviderListRow(
                        monitor: monitor,
                        tab: tab,
                        canMoveUp: index > 0,
                        canMoveDown: index < listedProducts.count - 1,
                        onMove: { listOrder = monitor.productTabs.map(\.id) }
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProviderId = tab.id
                        }
                    }
                }

                HStack {
                    if let importError {
                        Text(importError)
                            .font(theme.font(size: 10, weight: .semibold))
                            .foregroundStyle(theme.statusWarning)
                    }
                    Spacer()
                    Button("Import…", action: chooseImport)
                    Button("Add Provider…") { addingProvider = true }
                }
                .padding(.top, 4)
            }
        }
        .onAppear {
            listOrder = ProviderListOrder.listed(monitor.productTabs.map { ($0.id, $0.isEnabled) })
        }
        .sheet(isPresented: $addingProvider) {
            AddProviderSheet(monitor: monitor) { addingProvider = false }.themedSheet()
        }
        .sheet(item: $importing) { review in
            ImportProviderSheet(monitor: monitor, review: review.value) { importing = nil }.themedSheet()
        }
    }

    /// Every product, in the order the list took when it appeared.
    private var listedProducts: [ProductTab] {
        let all = monitor.productTabs
        let order = ProviderListOrder.keeping(listOrder, current: all.map(\.id))
        return order.compactMap { id in all.first { $0.id == id } }
    }

    /// *Import…*: a shared file is read and reviewed — nothing is saved or run yet.
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                importError = nil
                let file = try String(contentsOf: url, encoding: .utf8)
                guard let review = try value(of: Kit.shared.workshop.review(file: file)) else { return }
                importing = IdentifiedReview(value: review)
            } catch {
                importError = "Not a ClaudeBar provider: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - List Row

private struct ProviderListRow: View {
    let monitor: QuotaMonitor
    /// The product — one row, however many logins it has (CANONICAL §1: the product's switch).
    let tab: ProductTab
    let canMoveUp: Bool
    let canMoveDown: Bool
    /// Runs after a move persists, so the pane's frozen list order picks the
    /// change up immediately instead of waiting for the next appear.
    let onMove: () -> Void
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    private var statusText: String {
        guard tab.isEnabled else { return "Disabled" }
        let updated = tab.accounts.compactMap { $0.snapshot?.capturedAt }.max()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let when = updated.map { "Updated \(formatter.localizedString(for: $0, relativeTo: Date()))" } ?? "No data yet"
        return tab.accounts.count > 1 ? "\(tab.accounts.count) accounts · \(when)" : when
    }

    var body: some View {

        let _ = KitObservation.track()
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ProviderIconView(providerId: tab.id, size: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppSettings.shared.shown(tab.name))
                        .font(theme.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Text(statusText)
                        .font(theme.font(size: 10, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer()

                if tab.isEnabled {
                    // Each login's usage, one meter per login (by name when there are several).
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(tab.accounts, id: \.id) { login in
                            if let quota = monitor.usage(of: login)?.lowestQuota {
                                LoginMeter(name: tab.loginName(login: login).map(AppSettings.shared.shown), quota: quota)
                            }
                        }
                    }
                }

                reorderControls

                SettingsSwitch(isOn: Binding(
                    get: { tab.isEnabled },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            monitor.setProductEnabled(tab: tab, enabled: newValue)
                        }
                    }
                ))

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient).themeShadow(theme)
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                            .stroke(isHovering ? theme.glassHighlight : theme.glassBorder, lineWidth: theme.cardBorderWidth)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                            .fill(isHovering ? theme.hoverOverlay : Color.clear)
                    )
            )
            .opacity(tab.isEnabled ? 1 : 0.55)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    /// Up/down controls that persist the provider order (issue #141). The
    /// menu bar pills, the overview and ⌘1–⌘9 all read the same order through
    /// QuotaMonitor, so this is the single place users shape it.
    private var reorderControls: some View {
        VStack(spacing: 0) {
            moveButton(symbol: "chevron.up", offset: -1, enabled: canMoveUp, label: "Move \(tab.name) up")
            moveButton(symbol: "chevron.down", offset: 1, enabled: canMoveDown, label: "Move \(tab.name) down")
        }
    }

    private func moveButton(symbol: String, offset: Int, enabled: Bool, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                monitor.providers.move(tab.id, by: offset)
                onMove()
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary.opacity(0.35))
                .frame(width: 18, height: 13)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Detail

/// Per-provider configuration: reuses the existing provider config cards
/// from the popover settings, plus the custom web card URL field.
private struct ProviderDetailView: View {
    let monitor: QuotaMonitor
    /// The product: its name and its switch head the page.
    let tab: ProductTab
    /// What the page configures — the product's plain login (`tab.page`).
    let provider: Account
    let onBack: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                backButton

                HStack(spacing: 14) {
                    ProviderIconView(providerId: provider.id, size: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppSettings.shared.shown(tab.name))
                            .font(theme.font(size: 21, weight: .bold))
                            .foregroundStyle(theme.textPrimary)

                        Text(tab.isEnabled ? "Enabled" : "Disabled")
                            .font(theme.font(size: 11, weight: .semibold))
                            .foregroundStyle(tab.isEnabled ? theme.statusHealthy : theme.textTertiary)
                    }

                    Spacer()

                    SettingsSwitch(isOn: Binding(
                        get: { tab.isEnabled },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                monitor.setProductEnabled(tab: tab, enabled: newValue)
                            }
                        }
                    ))
                }
                .padding(.bottom, 6)

                if tab.isEnabled {
                    configCard

                    QuotaVisibilityCard(provider: provider, monitor: monitor)

                    SettingsCard {
                        SettingsFieldLabel(text: "CUSTOM WEB CARD")
                            .padding(.bottom, 8)

                        CustomCardURLField(providerId: provider.id)
                    }
                } else {
                    Text("Enable \(tab.name) to configure it.")
                        .font(theme.font(size: 12, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text("All Providers")
                    .font(theme.font(size: 11, weight: .semibold))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(theme.glassBackground)
                    .overlay(Capsule().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// A provider made from a definition gets the same sections as every
    /// other: its data source, its settings form and its accounts. A provider
    /// still on its own card keeps that card beside them until it moves to JSON.
    @ViewBuilder
    private var configCard: some View {
        let product = tab.provider
        let legacy = legacyCard(for: product.id)
        DataSourceSection(provider: product, monitor: monitor)
        if legacy == nil, !product.definition.defaultLoginSettings.isEmpty {
            ProviderSettingsSection(provider: product)
        }
        if product.definition.accounts != nil {
            ProviderAccountsCard(provider: product, monitor: monitor)
        }
        if let legacy { legacy }
        if product.definition.profile.origin == .custom {
            CustomProviderCard(provider: product, monitor: monitor, onDeleted: onBack)
        }
    }

    /// The card a provider has before its settings are a form — gone as each
    /// one moves to JSON (ENGINE_DESIGN §2.2).
    private func legacyCard(for id: String) -> AnyView? {
        switch id {
        case "claude": AnyView(ClaudeBudgetCard())
        case "deepseek": AnyView(DeepSeekConfigCard(monitor: monitor))
        default: nil
        }
    }
}

// MARK: - Quotas (issue #140)

/// *QUOTAS* — one switch per quota the provider reports, so a person can
/// stop watching the ones they never use (Gemini Flash 2.0, …). A hidden
/// quota is never shown and never sets a status or an alert, anywhere: the
/// monitor leaves it out of the usage every surface reads.
private struct QuotaVisibilityCard: View {
    let provider: Account
    let monitor: QuotaMonitor

    @Environment(\.appTheme) private var theme
    @State private var refused: String?

    var body: some View {

        let _ = KitObservation.track()
        SettingsCard {
            SettingsFieldLabel(text: "QUOTAS")
                .padding(.bottom, 12)

            if let quotas = provider.snapshot?.quotas, quotas.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(quotas.enumerated()), id: \.element.quotaType) { index, quota in
                        if index > 0 {
                            SettingsRowDivider()
                        }
                        toggleRow(quota)
                    }
                }
                Text(refused ?? "Turn off a quota you don't use: it disappears everywhere and no longer sets \(monitor.lineupName(of: provider))'s status or alerts.")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(refused == nil ? theme.textTertiary : theme.statusWarning)
                    .padding(.top, 8)
            } else {
                Text("No quotas to choose from yet. Refresh \(monitor.lineupName(of: provider)) once, then pick the ones you watch.")
                    .font(theme.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func toggleRow(_ quota: UsageQuota) -> some View {
        let key = quota.quotaType.quotaKey
        return SettingsRow(title: quota.compactTitle ?? quota.quotaType.displayName, subtitle: nil) {
            SettingsSwitch(isOn: Binding(
                get: { !monitor.hiddenQuotaKeys(of: provider).contains(key) },
                set: { watched in
                    refused = monitor.setQuota(key: key, hidden: !watched, of: provider)
                        ? nil : "Keep at least one quota: \(monitor.lineupName(of: provider)) needs something to watch."
                }
            ))
        }
    }
}

/// A review to present as a sheet.
struct IdentifiedReview: Identifiable {
    let id = UUID()
    let value: ImportReview
}

/// One login's usage on a product's row: its name when the product has
/// several, the tightest quota's share or money left, and a meter.
private struct LoginMeter: View {
    let name: String?
    let quota: UsageQuota
    @Environment(\.appTheme) private var theme

    var body: some View {

        let _ = KitObservation.track()
        let color = theme.statusColor(for: quota.status(under: AppSettings.shared.statusPolicy))
        HStack(spacing: 6) {
            if let name {
                Text(name)
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            if let percent = quota.percentLeft {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.progressTrack)
                        Capsule().fill(color).frame(width: geo.size.width * max(0, min(100, percent)) / 100)
                    }
                }
                .frame(width: 70, height: 4)
            }
            Text(quota.percentLeft.map { "\(Int($0))%" } ?? quota.formattedDollarRemaining ?? "—")
                .font(theme.font(size: 11, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
                .frame(minWidth: 30, alignment: .trailing)
        }
    }
}
