import SwiftUI
import Domain
import Infrastructure

/// AWS Bedrock provider configuration card for SettingsView.
struct BedrockConfigCard: View {
    @ObservedObject var monitor: QuotaMonitor

    @ObservedObject var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var bedrockConfigExpanded: Bool = false
    @State private var awsProfileNameInput: String = ""
    @State private var bedrockRegionsInput: String = ""
    @State private var bedrockDailyBudgetInput: String = ""

    var body: some View {
        DisclosureGroup(isExpanded: $bedrockConfigExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                // AWS Profile Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("AWS PROFILE NAME")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)

                    TextField("", text: $awsProfileNameInput, prompt: Text("default").foregroundColor(theme.textTertiary))
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
                        .onChange(of: awsProfileNameInput) { newValue in
                            settings.bedrock.setAWSProfileName(newValue)
                        }
                }

                // Regions
                VStack(alignment: .leading, spacing: 6) {
                    Text("REGIONS (COMMA-SEPARATED)")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)

                    TextField("", text: $bedrockRegionsInput, prompt: Text("us-east-1, us-west-2").foregroundColor(theme.textTertiary))
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
                        .onChange(of: bedrockRegionsInput) { newValue in
                            let regions = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            settings.bedrock.setBedrockRegions(regions)
                        }
                }

                // Daily Budget
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAILY BUDGET (USD, OPTIONAL)")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.textSecondary)

                    HStack(spacing: 6) {
                        Text("$")
                            .font(.system(size: 12, weight: .medium, design: theme.fontDesign))
                            .foregroundColor(theme.textSecondary)

                        TextField("", text: $bedrockDailyBudgetInput, prompt: Text("50.00").foregroundColor(theme.textTertiary))
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
                            .onChange(of: bedrockDailyBudgetInput) { newValue in
                                if newValue.isEmpty {
                                    settings.bedrock.setBedrockDailyBudget(nil)
                                } else if let value = Decimal(string: newValue) {
                                    settings.bedrock.setBedrockDailyBudget(value)
                                }
                            }
                    }
                }

                // Help text
                VStack(alignment: .leading, spacing: 4) {
                    Text("AWS credentials are loaded from your configured profile.")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.textTertiary)

                    Text("Configure with: aws configure --profile <name>")
                        .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        .foregroundColor(theme.textTertiary)
                }

                // Link to AWS console
                Link(destination: URL(string: "https://console.aws.amazon.com/bedrock/home")!) {
                    HStack(spacing: 3) {
                        Text("Open Bedrock Console")
                            .font(.system(size: 9, weight: .semibold, design: theme.fontDesign))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundColor(theme.accentPrimary)
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.6, blue: 0.0),
                                    Color(red: 0.9, green: 0.45, blue: 0.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AWS Bedrock Configuration")
                        .font(.system(size: 14, weight: .bold, design: theme.fontDesign))
                        .foregroundColor(theme.textPrimary)

                    Text("CloudWatch usage tracking")
                        .font(.system(size: 10, weight: .medium, design: theme.fontDesign))
                        .foregroundColor(theme.textTertiary)
                }

                Spacer()
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bedrockConfigExpanded.toggle()
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
                                colors: [theme.glassBorder, theme.glassBorder.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .onAppear {
            awsProfileNameInput = settings.bedrock.awsProfileName()
            bedrockRegionsInput = settings.bedrock.bedrockRegions().joined(separator: ", ")
            if let budget = settings.bedrock.bedrockDailyBudget() {
                bedrockDailyBudgetInput = String(describing: budget)
            }
        }
    }
}
