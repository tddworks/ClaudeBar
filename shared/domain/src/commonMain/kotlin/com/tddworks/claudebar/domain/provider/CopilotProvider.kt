package com.tddworks.claudebar.domain.provider

/**
 * GitHub Copilot AI provider - a rich domain model.
 */
class CopilotProvider(
    probe: UsageProbe,
    settingsRepository: ProviderSettingsRepository
) : BaseAIProvider(
    id = "copilot",
    name = "Copilot",
    cliCommand = "gh",
    dashboardURL = "https://github.com/settings/billing",
    statusPageURL = "https://www.githubstatus.com",
    probe = probe,
    settingsRepository = settingsRepository
)
