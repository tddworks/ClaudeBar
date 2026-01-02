package com.tddworks.claudebar.domain.provider

/**
 * Z.ai AI provider (GLM-based) - a rich domain model.
 */
class ZaiProvider(
    probe: UsageProbe,
    settingsRepository: ProviderSettingsRepository
) : BaseAIProvider(
    id = "zai",
    name = "Z.ai",
    cliCommand = "claude", // Uses Claude CLI with z.ai endpoint
    dashboardURL = "https://z.ai/dashboard",
    statusPageURL = null,
    probe = probe,
    settingsRepository = settingsRepository
)
