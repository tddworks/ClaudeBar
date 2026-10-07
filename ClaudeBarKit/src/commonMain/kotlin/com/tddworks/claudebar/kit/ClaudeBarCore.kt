package com.tddworks.claudebar.kit

import com.tddworks.claudebar.activity.HookInstaller
import com.tddworks.claudebar.activity.HookSettingsRepository
import com.tddworks.claudebar.activity.NewSessions
import com.tddworks.claudebar.activity.SessionMonitor
import com.tddworks.claudebar.activity.SessionTracking
import com.tddworks.claudebar.alerting.NotificationAlerter
import com.tddworks.claudebar.alerting.NotifyPublisher
import com.tddworks.claudebar.alerting.NotifySettingsRepository
import com.tddworks.claudebar.alerting.QuotaAlerts
import com.tddworks.claudebar.leaderboard.Leaderboard
import com.tddworks.claudebar.monitoring.QuotaMonitor
import com.tddworks.claudebar.providers.ProviderDefinition
import com.tddworks.claudebar.datasources.SecretVault
import com.tddworks.claudebar.providers.ProviderFactory
import com.tddworks.claudebar.providers.ProviderSettingsRepository
import com.tddworks.claudebar.providers.ProviderWorkshop
import com.tddworks.claudebar.storage.Revision
import com.tddworks.claudebar.storage.SettingsFile
import kotlinx.coroutines.flow.StateFlow

/**
 * The composition root (MODULAR_DESIGN §1): every context built once and wired, and the one
 * change signal the UI observes (§5). The App starts it and shows its state; nothing in Kotlin
 * reaches back to the App.
 */
public class ClaudeBarCore internal constructor(
    /** The single source of truth for every product and login. */
    public val monitor: QuotaMonitor,
    /** *Add Provider* and *Import*. */
    public val workshop: ProviderWorkshop,
    private val factory: ProviderFactory,
    private val providerSettings: ProviderSettingsRepository,
    private val vault: SecretVault,
    /** Drops every CLI location found so far. */
    private val forgetCLIs: () -> Unit,
    /** *New terminal sessions* — which login each CLI starts with. */
    public val newSessions: NewSessions,
    /** *Quota alerts* — the person's own percentages (#68). */
    public val quotaAlerts: QuotaAlerts,
    /** Status-change notifications. */
    public val notifications: NotificationAlerter,
    /** The leaderboard: membership, uploads and the board. */
    public val leaderboard: Leaderboard,
    public val notifySettings: NotifySettingsRepository,
    /** Keeps a linked Notify! device in sync with the quotas. */
    public val notifyPublisher: NotifyPublisher,
    /** `~/.claudebar/settings.json`, shared with the settings Swift still keeps. */
    public val settingsFile: SettingsFile,
    /** Claude Code's sessions, from its hooks. */
    public val sessions: SessionMonitor,
    /** The hook loop: on while hooks are on. */
    public val sessionTracking: SessionTracking,
    public val hookSettings: HookSettingsRepository,
    public val hookInstaller: HookInstaller,
) {
    /** The definition a lineup id belongs to — `codex.<account>` belongs to `codex`; null when none does. */
    public fun definition(lineupId: String): ProviderDefinition? = factory.definition(lineupId)

    /** The page a provider's card links to instead of its dashboard; null when the person set none. */
    public fun customCardURL(providerId: String): String? = providerSettings.customCardURL(providerId)

    public fun setCustomCardURL(url: String?, providerId: String) {
        providerSettings.setCustomCardURL(url, providerId)
    }

    /** A key saved for a provider — never logged, never written to settings.json. */
    public fun secret(name: String, providerId: String): String? = vault.secret(name, providerId)

    public fun saveSecret(value: String, name: String, providerId: String) {
        vault.save(value, name, providerId)
    }

    public fun deleteSecret(name: String, providerId: String): Boolean = vault.delete(name, providerId)

    /**
     * Looks for every CLI afresh — after the person installed or moved one, so it is picked up
     * at once instead of when the cached lookup expires.
     */
    public fun forgetFoundCLIs() {
        forgetCLIs()
    }

    /** Moves whenever anything the UI shows changes — one signal for the whole kit. */
    public val changes: StateFlow<Long> = Revision.any

    public companion object
}
