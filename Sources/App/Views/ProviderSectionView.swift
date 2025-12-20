import SwiftUI
import Domain

/// A section showing all quotas for a single AI provider.
/// Uses the rich UsageSnapshot domain model directly.
struct ProviderSectionView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(snapshot.provider.name)
                    .font(.headline)

                Spacer()

                if let email = snapshot.accountEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Quota grid
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(snapshot.quotas, id: \.quotaType) { quota in
                    QuotaCardView(quota: quota)
                }
            }

            // Age indicator
            HStack {
                Text("Updated \(snapshot.ageDescription)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if snapshot.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var statusColor: Color {
        switch snapshot.overallStatus {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        case .depleted: .red
        }
    }
}
