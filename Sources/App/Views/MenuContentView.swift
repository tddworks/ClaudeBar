import SwiftUI
import Domain

/// The main menu content view showing all monitored providers.
/// Directly binds to the QuotaMonitor domain service.
struct MenuContentView: View {
    @State private var snapshots: [AIProvider: UsageSnapshot] = [:]
    @State private var isRefreshing = false
    @State private var lastError: String?

    let monitor: QuotaMonitor

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Provider sections
            if snapshots.isEmpty && !isRefreshing {
                emptyStateView
            } else {
                providerListView
            }

            Divider()

            // Footer actions
            footerView
        }
        .frame(width: 320)
        .task {
            await refresh()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .font(.title2)
                .foregroundStyle(.primary)

            Text("ClaudeBar")
                .font(.headline)

            Spacer()

            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Circle()
                    .fill(overallStatusColor)
                    .frame(width: 10, height: 10)

                Text(overallStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Provider List

    private var providerListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedProviders, id: \.self) { provider in
                    if let snapshot = snapshots[provider] {
                        ProviderSectionView(snapshot: snapshot)

                        if provider != sortedProviders.last {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No providers available")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Install Claude, Codex, or Gemini CLI")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 200)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Refresh") {
                Task {
                    await refresh()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Helpers

    private var sortedProviders: [AIProvider] {
        AIProvider.allCases.filter { snapshots[$0] != nil }
    }

    private var overallStatusColor: Color {
        let status = snapshots.values.map(\.overallStatus).max() ?? .healthy
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        case .depleted: return .red
        }
    }

    private var overallStatusText: String {
        let status = snapshots.values.map(\.overallStatus).max() ?? .healthy
        switch status {
        case .healthy: return "Healthy"
        case .warning: return "Warning"
        case .critical: return "Critical"
        case .depleted: return "Depleted"
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            snapshots = try await monitor.refreshAll()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
