package com.tddworks.claudebar.domain.provider

/**
 * Codex AI provider - a rich domain model.
 */
class CodexProvider(
    probe: UsageProbe,
    settingsRepository: ProviderSettingsRepository
) : BaseAIProvider(
    id = "codex",
    name = "Codex",
    cliCommand = "codex",
    dashboardURL = "https://platform.openai.com/usage",
    statusPageURL = "https://status.openai.com",
    probe = probe,
    settingsRepository = settingsRepository
)
