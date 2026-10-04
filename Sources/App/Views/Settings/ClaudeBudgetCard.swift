import SwiftUI
import Domain

/// The Claude API Budget — the person's own ceiling on Claude's API cost.
/// A budget belongs to the account whose cost it judges (CANONICAL_MODEL §1),
/// so it is its own card beside the Data source section.
struct ClaudeBudgetCard: View {
    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var claudeBudgetExpanded: Bool = false
    @State private var budgetInput: String = ""

    var body: some View {
        DisclosureGroup(isExpanded: $claudeBudgetExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            budgetForm
                .disabled(!settings.claudeApiBudgetEnabled)
                .opacity(settings.claudeApiBudgetEnabled ? 1 : 0.6)
        } label: {
            budgetHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        claudeBudgetExpanded.toggle()
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
            if settings.claudeApiBudget > 0 {
                budgetInput = String(describing: settings.claudeApiBudget)
            }
        }
    }

    private var budgetHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.85, green: 0.55, blue: 0.35),
                                Color(red: 0.75, green: 0.40, blue: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude API Budget")
                    .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.textPrimary)

                Text("Cost threshold warnings")
                    .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            SettingsSwitch(isOn: $settings.claudeApiBudgetEnabled)
                .accessibilityLabel("Claude API Budget")
        }
    }

    private var budgetForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MONTHLY BUDGET (USD)")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .tracking(0.5)

                HStack(spacing: 6) {
                    Text("$")
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textSecondary)

                    TextField("", text: $budgetInput, prompt: Text("10.00").foregroundStyle(theme.textTertiary))
                        .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(theme.glassBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                                )
                        )
                        .onChange(of: budgetInput) { _, newValue in
                            if let value = Decimal(string: newValue) {
                                settings.claudeApiBudget = value
                            }
                        }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Get warnings when approaching your budget threshold.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)

                Text("Only applies to Claude API accounts, not Claude Max.")
                    .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
