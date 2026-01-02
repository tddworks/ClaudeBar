package com.tddworks.claudebar.domain.provider

/**
 * Gemini AI provider - a rich domain model.
 */
class GeminiProvider(
    probe: UsageProbe,
    settingsRepository: ProviderSettingsRepository
) : BaseAIProvider(
    id = "gemini",
    name = "Gemini",
    cliCommand = "gemini",
    dashboardURL = "https://aistudio.google.com",
    statusPageURL = "https://status.cloud.google.com",
    probe = probe,
    settingsRepository = settingsRepository
)
