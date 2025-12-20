import SwiftUI
import Domain
import Infrastructure

@main
struct ClaudeBarApp: App {
    /// The main domain service - monitors all AI providers
    @State private var monitor: QuotaMonitor

    init() {
        // Create probes for each provider
        let probes: [any UsageProbePort] = [
            ClaudeUsageProbe(),
            // Add more probes here as needed:
            // CodexUsageProbe(),
            // GeminiUsageProbe(),
        ]

        // Initialize the domain service
        _monitor = State(initialValue: QuotaMonitor(probes: probes))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
        } label: {
            StatusBarIcon(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon that reflects the overall quota status
struct StatusBarIcon: View {
    let monitor: QuotaMonitor
    @State private var lowestPercent: Double = 100

    var body: some View {
        Image(systemName: iconName)
            .task {
                await updateIcon()
            }
    }

    private var iconName: String {
        if lowestPercent <= 0 {
            return "chart.bar.xaxis"
        } else if lowestPercent < 20 {
            return "chart.bar.fill"
        } else if lowestPercent < 50 {
            return "chart.bar.fill"
        } else {
            return "chart.bar.fill"
        }
    }

    private func updateIcon() async {
        if let lowest = await monitor.lowestQuota() {
            lowestPercent = lowest.percentRemaining
        }
    }
}
