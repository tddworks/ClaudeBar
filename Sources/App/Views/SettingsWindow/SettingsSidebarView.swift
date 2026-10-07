import SwiftUI
import Kit

/// Full-height sidebar for the Settings window. Hosts the traffic-light
/// gap at the top (the window has a hidden title bar), grouped navigation,
/// and a version footer.
struct SettingsSidebarView: View {
    let monitor: QuotaMonitor
    @Binding var selection: SettingsSection
    var filter: String = ""

    @Environment(\.appTheme) private var theme
    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif

    private var visibleSections: Set<SettingsSection> {
        Set(SettingsSection.matching(filter: filter))
    }

    private var updateStatus: UpdateStatus {
        #if ENABLE_SPARKLE
        UpdateStatus(updater: sparkleUpdater)
        #else
        .installed
        #endif
    }

    private var updateStatusColor: Color {
        updateStatus.availableVersion == nil ? theme.statusHealthy : theme.statusWarning
    }

    private var enabledProviderCount: Int {
        monitor.productTabs.filter(\.isEnabled).count
    }

    private var totalProviderCount: Int {
        monitor.productTabs.count
    }

    var body: some View {

        let _ = KitObservation.track()
        VStack(alignment: .leading, spacing: 2) {
            // Traffic lights overlay this region (hidden title bar).
            Color.clear
                .frame(height: 34)

            HStack(spacing: 8) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                Text("ClaudeBar")
                    .font(theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ForEach(SettingsSectionGroup.allCases) { group in
                let sections = group.sections.filter { visibleSections.contains($0) }

                if !sections.isEmpty {
                    Text(group.title.uppercased())
                        .font(theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .tracking(1.2)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(sections) { section in
                        SidebarItem(
                            section: section,
                            isSelected: selection == section,
                            badge: section == .providers ? "\(enabledProviderCount)/\(totalProviderCount)" : nil
                        ) {
                            selection = section
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Circle()
                    .fill(updateStatusColor)
                    .frame(width: 7, height: 7)

                Text(updateStatus.footer)
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 10)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.isOutlined ? AnyShapeStyle(theme.progressTrack.opacity(0.45)) : AnyShapeStyle(Color.black.opacity(0.15)))
        .overlay(alignment: .trailing) {
            if theme.isOutlined {
                Rectangle().fill(theme.glassBorder).frame(width: theme.cardBorderWidth)
            }
        }
    }
}

private struct SidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    var badge: String? = nil
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {

        let _ = KitObservation.track()
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AnyShapeStyle(theme.accentGradient) : AnyShapeStyle(theme.glassBackground))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.isOutlined ? theme.glassBorder : .clear, lineWidth: theme.cardBorderWidth * 0.7))
                        .frame(width: 24, height: 24)

                    Image(systemName: section.symbolName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected && theme.id != "cli" ? .white : theme.textSecondary)
                }

                Text(section.title)
                    .font(theme.font(size: 13, weight: theme.isOutlined ? .bold : .medium))
                    .foregroundStyle(isSelected ? (theme.isOutlined ? theme.glassBackground : theme.textPrimary) : theme.textSecondary)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(theme.font(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.glassBackground))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                // An outlined theme inks the selected row; glass tints it.
                RoundedRectangle(cornerRadius: theme.isOutlined ? 12 : 9)
                    .fill(isSelected ? (theme.isOutlined ? theme.textPrimary : theme.accentPrimary.opacity(0.15))
                                     : (isHovering ? theme.hoverOverlay : Color.clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.isOutlined ? 12 : 9)
                            .stroke(isSelected && !theme.isOutlined ? theme.accentPrimary.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
