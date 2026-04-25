import SwiftUI
import Domain

/// A section showing all quotas for a single AI provider.
/// Uses the rich UsageSnapshot domain model directly.
struct ProviderSectionView: View {
    let snapshot: UsageSnapshot

    @ObservedObject var settings = AppSettings.shared

    private var effectiveOverallStatus: QuotaStatus {
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(effectiveOverallStatus.displayColor)
                    .frame(width: 8, height: 8)

                Text(providerDisplayName)
                    .font(.headline)

                Spacer()

                if let email = snapshot.accountEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    .foregroundColor(Color(.tertiaryLabelColor))

                if snapshot.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
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

    private var providerDisplayName: String {
        ProviderVisualIdentityLookup.name(for: snapshot.providerId)
    }
}
