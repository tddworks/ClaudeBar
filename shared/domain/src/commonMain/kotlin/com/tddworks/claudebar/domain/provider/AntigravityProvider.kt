package com.tddworks.claudebar.domain.provider

/**
 * Antigravity AI provider (Codeium-based) - a rich domain model.
 */
class AntigravityProvider(
    probe: UsageProbe,
    settingsRepository: ProviderSettingsRepository
) : BaseAIProvider(
    id = "antigravity",
    name = "Antigravity",
    cliCommand = "antigravity",
    dashboardURL = "https://codeium.com/profile",
    statusPageURL = null,
    probe = probe,
    settingsRepository = settingsRepository
)
