package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.storage.SettingsFile

/**
 * Extensions became definitions (docs/features/extensions/design.md). What a person saved for
 * one moves once, by the same names: a value from `extensions.<id>.<field>` into the provider's
 * settings, a secret from UserDefaults into the vault (the Keychain) — and out of UserDefaults.
 * Recorded per extension, so a later change is never overwritten.
 */
internal object ExtensionSettingsUpgrade {
    const val DONE = "upgradedFromExtension"

    fun run(
        definitions: List<ProviderDefinition>,
        file: SettingsFile,
        settings: ProviderSettingsRepository,
        vault: SecretVault,
        defaults: LegacyStore,
    ) {
        for (definition in definitions.filter { it.profile.origin == ProviderProfile.Origin.EXTENSION }) {
            if (settings.isOn(DONE, definition.id) == true) continue
            val extensionId = definition.id.removePrefix("ext-")
            for (setting in definition.settings) {
                if (setting.kind == Setting.Kind.Secret) {
                    val key = "com.claudebar.credentials.ext-$extensionId-${setting.id}"
                    val value = defaults.string(key)
                    if (!value.isNullOrEmpty()) {
                        vault.save(value, setting.id, definition.id)
                        defaults.remove(key)
                    }
                } else {
                    file.string("extensions.$extensionId.${setting.id}")?.let { settings.setValue(it, setting.id, definition.id) }
                }
            }
            settings.setOn(true, DONE, definition.id)
            AppLog.providers.info("Extension $extensionId: its saved settings now belong to its definition")
        }
    }
}
