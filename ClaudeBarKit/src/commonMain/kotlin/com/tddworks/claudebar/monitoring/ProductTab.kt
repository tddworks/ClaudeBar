package com.tddworks.claudebar.monitoring

import com.tddworks.claudebar.providers.Account
import com.tddworks.claudebar.providers.Provider
import com.tddworks.claudebar.providers.Providers

/**
 * A pill in the popover: one product with every enabled login of it — three Claude logins are
 * one *Claude* tab, side by side, not three tabs. Its logins come in the person's order.
 */
internal class ProductTab(
    /** The product. */
    val provider: Provider,
    /** Its logins in the lineup, in the person's order. */
    val accounts: List<Account>,
) {
    /** The product's id — `codex`, never `codex.<acct>`. */
    val id: String get() = provider.id
    val name: String get() = provider.name

    /** The product's own switch (CANONICAL §1). */
    val isEnabled: Boolean get() = provider.isEnabled

    /** A login's name on the product's row — only when there are several to tell apart. */
    fun loginName(login: Account): String? = if (accounts.size > 1) login.displayName else null

    /** What the product's page configures: its plain login, whose id the configuration is keyed by. */
    val page: Account get() = provider.defaultAccount

    fun contains(lineupId: String): Boolean = accounts.any { it.id == lineupId }

    companion object {
        /** The lineup as tabs, in the order products first appear in it — each login's product found through the root. */
        fun tabs(lineup: List<Account>, providers: Providers): List<ProductTab> {
            val shown = lineup.map { it.id }.toSet()
            val seen = mutableSetOf<String>()
            return lineup.mapNotNull { login ->
                val product = providers.provider(of = login) ?: return@mapNotNull null
                if (!seen.add(product.id)) return@mapNotNull null
                ProductTab(product, product.accounts.filter { it.id in shown })
            }
        }
    }
}
