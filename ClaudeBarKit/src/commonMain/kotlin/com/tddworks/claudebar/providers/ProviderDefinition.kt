package com.tddworks.claudebar.providers

import com.tddworks.claudebar.datasources.process.SignInCall

import com.tddworks.claudebar.datasources.DataSourceDefinition
import com.tddworks.claudebar.datasources.DefinitionError
import com.tddworks.claudebar.datasources.Fetch
import com.tddworks.claudebar.datasources.IdentityField
import com.tddworks.claudebar.datasources.bool
import com.tddworks.claudebar.datasources.decoding
import com.tddworks.claudebar.datasources.int
import com.tddworks.claudebar.datasources.logs.UsageLog
import com.tddworks.claudebar.datasources.lookup.CredentialLookup
import com.tddworks.claudebar.datasources.lookup.CredentialRefresh
import com.tddworks.claudebar.datasources.requireString
import com.tddworks.claudebar.datasources.string
import com.tddworks.claudebar.quotas.AccountTier
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import org.kotlincrypto.hash.sha2.SHA256

/**
 * A provider as data — what ships in `Resources/Providers/<id>.json` for a built-in, and what
 * *Add Provider* writes for a custom one. Validated when parsed, so a `Provider` is only ever
 * made from a definition that keeps the laws below. Made through `ProviderDefinition(…)`, which
 * folds the account form into the settings: one form, asked by Settings and *Add Account* alike.
 */
@ConsistentCopyVisibility
internal data class ProviderDefinition private constructor(
    /** WHO IT IS — the only place an id becomes a face. */
    val profile: ProviderProfile,
    /** The CLI a person would run, when there is one. */
    val cli: String?,
    /** Where else this CLI may be when `cli` isn't on the PATH — the copy a product's own app carries. */
    val cliPlaces: List<String>,
    val enabledByDefault: Boolean,
    /** Where the product sits in the lineup by default; none → after the rest, by name (TARGET_ARCHITECTURE §10). */
    val order: Int?,
    /** The guest-passes capability (CANONICAL §2.1), declared `"guestPasses": {}`. */
    val guestPasses: Boolean,
    val dataSources: List<DataSourceDefinition>,
    val defaultDataSource: String,
    /** Every data source answers on each refresh and the usage is their union — an extension's sections. */
    val together: Boolean,
    /** Logins added beside the default one, and how they differ. */
    val accounts: Accounts?,
    /** What it needs from the person; the account-scope ones are what *Add Account* asks for. */
    val settings: List<Setting>,
    /** *TODAY'S USAGE* — how to extract a login's usage history from its tool's own logs. */
    val usageHistory: UsageLog.Definition?,
    /** What it takes to see this provider's limits, said where an error would otherwise be. */
    val setup: Setup?,
) {
    /** Stable forever: settings, the menu-bar choice and the lineup are keyed by it. */
    val id: String get() = profile.id

    /** What *Add Account*'s form asks for: the account-scope settings. */
    val accountSettings: List<Setting> get() = settings.filter { it.scope == Setting.Scope.ACCOUNT }

    fun setting(id: String): Setting? = settings.firstOrNull { it.id == id }

    fun dataSource(kind: String): DataSourceDefinition? = dataSources.firstOrNull { it.kind == kind }

    /**
     * The settings the default login uses — those its data sources or dashboard name, as
     * `{{setting.x}}` or a `setting` lookup. A folder only an added login has is not one of
     * them, so Settings never shows a field that changes nothing.
     */
    val defaultLoginSettings: List<Setting>
        get() {
            val text = JsonArray(dataSources.map { it.toJson() }).toString() + (profile.links.dashboardTemplate ?: "")
            return settings.filter { setting ->
                text.contains("{{setting.${setting.id}}}") || text.contains("{{setting.${setting.id}.") ||
                    text.contains("\"setting\":\"${setting.id}\"")
            }
        }

    /**
     * The data sources an added login runs: each with `accounts.patch` merged in (RFC 7396) and
     * `{{account.<name>}}` filled from the login's [values]. A source that needs a value only
     * some sources ask for (`"for"`) is left out of a login added without it; a value every
     * source asks for, missing, throws.
     */
    fun dataSourcesForAccount(values: Map<String, String>): List<DataSourceDefinition> {
        val patch = accounts?.patch ?: emptyMap()
        return dataSources.mapNotNull { source ->
            var adapted = source
            val change = patch[source.kind]
            if (change != null) {
                if (change is JsonNull) return@mapNotNull null
                adapted = source.patched(change)
            }
            adapted = adapted.filled(values, "account")
            val missing = adapted.unfilled("account").firstOrNull()
            if (missing != null) {
                if (accountSettings.any { it.id == missing && it.dataSources.isNotEmpty() }) return@mapNotNull null
                throw DefinitionErrors.missingAccountValue(id, missing)
            }
            adapted
        }
    }

    /**
     * The usage history an added login reads: `accounts.patch.usageHistory` merged in and
     * `{{account.<name>}}` filled. Null when the patch doesn't say where the login's own logs
     * are — it would read the default login's — or a value is missing.
     */
    fun usageHistoryForAccount(values: Map<String, String>): UsageLog.Definition? {
        val history = usageHistory ?: return null
        val patch = accounts?.patch?.get("usageHistory") ?: return null
        if (patch is JsonNull) return null
        val adapted = runCatching { history.patched(patch).filled(values, "account") }.getOrNull() ?: return null
        return adapted.takeIf { it.unfilled("account").isEmpty() }
    }

    /** The laws: at least one data source, kinds unique, the default and every hand-off naming one of them. */
    fun validate() {
        if (dataSources.isEmpty()) throw DefinitionErrors.noDataSources(id)
        val kinds = mutableSetOf<String>()
        for (source in dataSources) {
            if (!kinds.add(source.kind)) throw DefinitionErrors.duplicateKind(id, source.kind)
        }
        if (defaultDataSource !in kinds) throw DefinitionErrors.unknownDataSource(id, defaultDataSource)
        val handOffs = dataSources.flatMap { listOfNotNull(it.fallback?.to) + it.fallbackOn.values }
        handOffs.firstOrNull { it !in kinds }?.let { throw DefinitionErrors.unknownDataSource(id, it) }
    }

    /**
     * The same definition running [binary] instead of its CLI's name — the person's *CLI
     * location* (#210). Only the executable changes, for every CLI and JSON-RPC data source,
     * every credential refresh that runs the CLI, and *Add Account*'s sign-in. It reaches a
     * subprocess as argv[0], never a shell line. Blank or unchanged is a no-op.
     */
    fun runningCLI(binary: String): ProviderDefinition {
        val path = binary.trim()
        val cli = cli
        if (cli == null || path.isEmpty() || path == cli) return this
        val sources = dataSources.map { source ->
            source.copy(fetch = source.fetch.runningCLI(cli, path), credential = source.credential?.runningCLI(cli, path))
        }
        val signIn = accounts?.signIn
        val accounts = if (signIn != null && signIn.cli == cli) accounts.copy(signIn = signIn.copy(cli = path)) else accounts
        // As Swift rebuilds it: `order` and `guestPasses` are not carried over.
        return invoke(
            profile = profile, cli = cli, cliPlaces = cliPlaces, enabledByDefault = enabledByDefault,
            dataSources = sources, defaultDataSource = defaultDataSource, together = together, accounts = accounts,
            settings = settings, usageHistory = usageHistory, setup = setup,
        )
    }

    /** The same definition, as loaded from [origin]. */
    fun withOrigin(origin: ProviderProfile.Origin): ProviderDefinition = copy(profile = profile.copy(origin = origin))

    fun toJson(): JsonObject = JsonObject(buildMap {
        put("profile", profile.toJson())
        cli?.let { put("cli", if (cliPlaces.isEmpty()) JsonPrimitive(it) else JsonArray((listOf(it) + cliPlaces).map(::JsonPrimitive))) }
        put("enabledByDefault", JsonPrimitive(enabledByDefault))
        order?.let { put("order", JsonPrimitive(it)) }
        put("dataSources", JsonArray(dataSources.map { it.toJson() }))
        put("defaultDataSource", JsonPrimitive(defaultDataSource))
        if (together) put("together", JsonPrimitive(true))
        accounts?.let { put("accounts", it.toJson()) }
        if (settings.isNotEmpty()) put("settings", JsonArray(settings.map { it.toJson() }))
        usageHistory?.let { put("usageHistory", it.toJson()) }
        setup?.let { put("setup", it.toJson()) }
        if (guestPasses) put("guestPasses", JsonObject(emptyMap()))
    })

    /** *SET UP* — a title, what it takes, and where to start. */
    data class Setup(
        val title: String,
        val text: String,
        val url: String? = null,
        /** The button that opens `url`, named for what it sets up. */
        val button: String = "Set up",
    ) {
        fun toJson(): JsonObject = JsonObject(buildMap {
            put("title", JsonPrimitive(title))
            put("text", JsonPrimitive(text))
            url?.let { put("url", JsonPrimitive(it)) }
            put("button", JsonPrimitive(button))
        })

        companion object {
            fun from(json: JsonElement): Setup {
                val o = json as? JsonObject ?: throw DefinitionError("setup is an object")
                return Setup(o.requireString("title", "setup"), o.requireString("text", "setup"), o.string("url"), o.string("button") ?: "Set up")
            }

            /** For a definition with no `setup`: *Set up <name>*, and what failed. */
            fun fallback(name: String, error: Throwable?): Setup = Setup("Set up $name", error?.message ?: "")
        }
    }

    /** The provider's links. The dashboard is a template: `{{setting.x}}` may fill it per login. */
    data class Links(
        val dashboardTemplate: String? = null,
        val status: String? = null,
        /** A different dashboard for some plans, keyed by the plan names mapping scripts use, or a badge as written. */
        val dashboardByPlan: Map<String, String> = emptyMap(),
    ) {
        /** The dashboard, when it names no setting. */
        val dashboard: String? get() = filling(emptyMap())

        /** The dashboard for the plan the last usage reported, else the default with a login's settings filled in. */
        fun dashboard(plan: AccountTier?, settings: Map<String, String> = emptyMap()): String? {
            if (plan != null) dashboardByPlan[key(plan)]?.let { return it }
            return filling(settings)
        }

        private fun filling(settings: Map<String, String>): String? {
            var text = dashboardTemplate ?: return null
            for ((name, value) in settings) text = text.replace("{{setting.$name}}", value)
            return text.takeUnless { it.contains("{{") || it.isEmpty() }
        }

        fun toJson(): JsonObject = JsonObject(buildMap {
            dashboardTemplate?.let { put("dashboard", JsonPrimitive(it)) }
            status?.let { put("status", JsonPrimitive(it)) }
            put("dashboardByPlan", JsonObject(dashboardByPlan.mapValues { JsonPrimitive(it.value) }))
        })

        companion object {
            fun key(plan: AccountTier): String = when (plan) {
                AccountTier.ClaudeMax -> "claudeMax"
                AccountTier.ClaudePro -> "claudePro"
                AccountTier.ClaudeApi -> "claudeApi"
                is AccountTier.Custom -> plan.badge
            }

            fun from(json: JsonElement): Links {
                val o = json as? JsonObject ?: throw DefinitionError("links is an object")
                return Links(o.string("dashboard"), o.string("status"), o.textMap("dashboardByPlan") ?: emptyMap())
            }
        }
    }

    /**
     * Logins a person adds beside the default one (#326). An added login runs the SAME data
     * sources with `patch` merged in (RFC 7396) and its saved values filling
     * `{{account.<name>}}` — one definition, never a copy per login.
     */
    data class Accounts(
        /** How a person adds one: by choosing the folder its login lives in. */
        val folder: Folder? = null,
        /** …or by running the vendor's login into a new folder, which `folder` then checks. */
        val signIn: SignInCall? = null,
        /** …or by filling in the account's own settings. Written once, as the definition's account-scope `settings`. */
        val form: List<Setting> = emptyList(),
        /** By data source kind, what an added login changes; `null` leaves that data source out for added logins. */
        val patch: Map<String, JsonElement> = emptyMap(),
    ) {
        /** The ways *Add Account* offers, easiest first. */
        val ways: List<AddAccountWay>
            get() = listOfNotNull(
                signIn?.let { AddAccountWay.SIGN_IN },
                folder?.let { AddAccountWay.FOLDER },
                if (form.isEmpty()) null else AddAccountWay.FORM,
            )

        // The form is written as the definition's account-scope settings; `accounts.form` is only read.
        fun toJson(): JsonObject = JsonObject(buildMap {
            folder?.let { put("folder", it.toJson()) }
            signIn?.let { put("signIn", it.toJson()) }
            put("patch", JsonObject(patch))
        })

        /**
         * `{ "savedAs": "home", "default": "${…_HOME:-~/.tool}", "accountId": { "field": "account", "savedAs": "accountId" } }`
         * — the folder and the login's account id are saved as the account's values;
         * `notSignedIn` is what a folder without a login says.
         */
        data class Folder(
            val savedAs: String,
            /** The default login's folder — never added a second time. */
            val default: String? = null,
            val accountId: AccountId,
            /** Where the login's email is read: a credential's `email` unless the definition says otherwise. */
            val email: IdentityField = IdentityField.CredentialValue("email"),
            /** Values saved beside the folder, by name, for `{{account.<name>}}`. */
            val derived: Map<String, Derived> = emptyMap(),
            val notSignedIn: String? = null,
        ) {
            /** The field that identifies the login, and the name its value is saved under. */
            data class AccountId(val field: IdentityField, val savedAs: String)

            /** `prefix` + the first `sha256` hex digits of the folder's path — how a CLI may name a config folder's Keychain item. */
            data class Derived(val prefix: String, val sha256: Int)

            /** The account's values for a chosen folder: the folder, and what is derived from it. */
            fun values(folder: String): Map<String, String> {
                val values = mutableMapOf(savedAs to folder)
                if (derived.isEmpty()) return values
                val hash = SHA256().digest(folder.encodeToByteArray())
                    .joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
                for ((name, rule) in derived) values[name] = rule.prefix + hash.take(maxOf(0, rule.sha256))
                return values
            }

            fun toJson(): JsonObject = JsonObject(buildMap {
                put("savedAs", JsonPrimitive(savedAs))
                default?.let { put("default", JsonPrimitive(it)) }
                put("accountId", JsonObject(mapOf("field" to JsonPrimitive(accountId.field.path), "savedAs" to JsonPrimitive(accountId.savedAs))))
                put("email", JsonPrimitive(email.path))
                put("derived", JsonObject(derived.mapValues { (_, rule) ->
                    JsonObject(mapOf("prefix" to JsonPrimitive(rule.prefix), "sha256" to JsonPrimitive(rule.sha256)))
                }))
                notSignedIn?.let { put("notSignedIn", JsonPrimitive(it)) }
            })

            companion object {
                fun from(json: JsonElement): Folder = decoding("accounts.folder") {
                    val o = json as? JsonObject ?: throw DefinitionError("accounts.folder is an object")
                    val id = o["accountId"] as? JsonObject ?: throw DefinitionError("accounts.folder needs \"accountId\"")
                    Folder(
                        savedAs = o.requireString("savedAs", "accounts.folder"),
                        default = o.string("default"),
                        accountId = AccountId(IdentityField.parse(id.requireString("field", "accountId")), id.requireString("savedAs", "accountId")),
                        email = o.string("email")?.let(IdentityField::parse) ?: IdentityField.CredentialValue("email"),
                        derived = (o.present("derived") as? JsonObject)?.mapValues { (name, rule) ->
                            val r = rule as? JsonObject ?: throw DefinitionError("derived.$name is an object")
                            Derived(r.requireString("prefix", "derived.$name"), r.int("sha256") ?: throw DefinitionError("derived.$name needs \"sha256\""))
                        } ?: emptyMap(),
                        notSignedIn = o.string("notSignedIn"),
                    )
                }
            }
        }

        companion object {
            fun from(json: JsonElement): Accounts {
                val o = json as? JsonObject ?: throw DefinitionError("accounts is an object")
                val folder = o.present("folder")?.let(Folder::from)
                val signIn = o.present("signIn")?.let(SignInCall::from)
                val form = (o.present("form")?.let { it as? JsonArray ?: throw DefinitionError("accounts.form is a list") }
                    ?.map(Setting::from) ?: emptyList()).map { it.inAccountScope }
                if (signIn != null && folder == null) {
                    throw DefinitionError("accounts.signIn needs accounts.folder to check the folder it signs into")
                }
                val patch = o.present("patch")?.let { it as? JsonObject ?: throw DefinitionError("accounts.patch is an object") } ?: emptyMap()
                return Accounts(folder, signIn, form, patch)
            }
        }
    }

    companion object {
        /** One form: the account-scope settings are also what *Add Account* asks. */
        operator fun invoke(
            profile: ProviderProfile,
            cli: String? = null,
            cliPlaces: List<String> = emptyList(),
            enabledByDefault: Boolean = true,
            dataSources: List<DataSourceDefinition>,
            defaultDataSource: String,
            together: Boolean = false,
            accounts: Accounts? = null,
            settings: List<Setting> = emptyList(),
            usageHistory: UsageLog.Definition? = null,
            setup: Setup? = null,
            order: Int? = null,
            guestPasses: Boolean = false,
        ): ProviderDefinition {
            val form = accounts?.form ?: emptyList()
            val all = settings + form.filter { field -> settings.none { it.id == field.id } }
            val accountScope = all.filter { it.scope == Setting.Scope.ACCOUNT }
            val folded = if (accounts != null) Accounts(accounts.folder, accounts.signIn, accountScope, accounts.patch)
            else if (accountScope.isEmpty()) null else Accounts(form = accountScope)
            return ProviderDefinition(
                profile, cli, cliPlaces, enabledByDefault, order, guestPasses, dataSources, defaultDataSource,
                together, folded, all, usageHistory, setup,
            )
        }

        /** Decodes and checks the laws; [origin] is whoever loads it — the file never says. */
        fun parse(text: String, origin: ProviderProfile.Origin = ProviderProfile.Origin.BUILT_IN): ProviderDefinition {
            val json = try {
                Json.parseToJsonElement(text)
            } catch (error: Exception) {
                throw DefinitionError("A provider definition is JSON: ${error.message}")
            }
            return from(json).withOrigin(origin).also { it.validate() }
        }

        /** The definition as written, with each setting's id used once; not yet [validate]d. */
        fun from(json: JsonElement): ProviderDefinition {
            val o = json as? JsonObject ?: throw DefinitionError("a provider definition is an object")
            val profile = ProviderProfile.from(o["profile"] ?: throw DefinitionError("a provider definition needs \"profile\""))
            return decoding("provider ${profile.id}") {
                val accounts = o.present("accounts")?.let(Accounts::from)
                val settings = o.present("settings")?.let { it as? JsonArray ?: throw DefinitionError("settings is a list") }
                    ?.map(Setting::from) ?: emptyList()
                // A file says each setting once: at the top, or in the old account form.
                accounts?.form?.firstOrNull { field -> settings.any { it.id == field.id } }?.let {
                    throw DefinitionError("Setting '${it.id}' is in both settings and accounts.form")
                }
                // `cli` is a name, or the name and the other places it may be.
                val cli = when (val value = o.present("cli")) {
                    null -> emptyList()
                    is JsonPrimitive -> if (value.isString) listOf(value.content) else throw DefinitionError("cli is a name or a list of them")
                    is JsonArray -> value.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content ?: throw DefinitionError("cli holds only text") }
                    else -> throw DefinitionError("cli is a name or a list of them")
                }
                val sources = o["dataSources"] as? JsonArray ?: throw DefinitionError("needs \"dataSources\"")
                val guestPasses = when (val value = o.present("guestPasses")) {
                    null -> false
                    is JsonObject -> true
                    else -> throw DefinitionError("guestPasses is an object")
                }
                // Through `invoke`, never the constructor: the old account form joins the settings.
                invoke(
                    profile = profile,
                    cli = cli.firstOrNull(),
                    cliPlaces = cli.drop(1),
                    enabledByDefault = o.bool("enabledByDefault") ?: true,
                    dataSources = sources.map(DataSourceDefinition::from),
                    defaultDataSource = o.requireString("defaultDataSource", "a provider definition"),
                    together = o.bool("together") ?: false,
                    accounts = accounts,
                    settings = settings,
                    usageHistory = o.present("usageHistory")?.let(UsageLog.Definition::from),
                    setup = o.present("setup")?.let(Setup::from),
                    order = o.int("order"),
                    guestPasses = guestPasses,
                ).also { it.validateSettings() }
            }
        }
    }

    /** Each setting's id is used once. */
    private fun validateSettings() {
        val ids = mutableSetOf<String>()
        settings.firstOrNull { !ids.add(it.id) }?.let { throw DefinitionErrors.duplicateSetting(id, it.id) }
    }
}

/** What a definition can be refused for, in the words Settings prints. */
internal object DefinitionErrors {
    fun noDataSources(id: String) = DefinitionError("Provider '$id' has no data sources")
    fun duplicateKind(id: String, kind: String) = DefinitionError("Provider '$id' lists data source '$kind' twice")
    fun unknownDataSource(id: String, kind: String) = DefinitionError("Provider '$id' names data source '$kind', which it doesn't have")
    fun missingFile(name: String) = DefinitionError("No provider definition named '$name'")
    fun missingAccountValue(id: String, name: String) = DefinitionError("A '$id' account has no saved '$name'")
    fun duplicateProvider(id: String) = DefinitionError("A provider named '$id' already exists")
    fun duplicateSetting(id: String, setting: String) = DefinitionError("Provider '$id' lists setting '$setting' twice")
    fun notDeletable(id: String) = DefinitionError("Provider '$id' isn't one you made; turn it off instead")
}

/** WHO IT IS — name, face and links; data, never a `when` on id. */
internal data class ProviderProfile(
    /** Stable forever: settings, the menu-bar choice and the lineup are keyed by it. */
    val id: String,
    val name: String,
    val links: ProviderDefinition.Links = ProviderDefinition.Links(),
    val look: ProviderLook = ProviderLook(),
    /** Not written in the file: whoever loads it knows where it came from. */
    val origin: Origin = Origin.BUILT_IN,
) {
    /** Where the definition came from — the badge Settings prints. */
    enum class Origin(val tag: String) {
        /** "Built in" — shipped in the app. */
        BUILT_IN("builtIn"),

        /** "Custom" — made in *Add Provider*, copied or imported. */
        CUSTOM("custom"),

        /** "Extension" — a manifest in `~/.claudebar/extensions/`. */
        EXTENSION("extension"),
    }

    fun toJson(): JsonObject = JsonObject(mapOf(
        "id" to JsonPrimitive(id),
        "name" to JsonPrimitive(name),
        "links" to links.toJson(),
        "look" to look.toJson(),
    ))

    companion object {
        fun from(json: JsonElement): ProviderProfile {
            val o = json as? JsonObject ?: throw DefinitionError("profile is an object")
            return ProviderProfile(
                id = o.requireString("id", "profile"),
                name = o.requireString("name", "profile"),
                links = o.present("links")?.let(ProviderDefinition.Links::from) ?: ProviderDefinition.Links(),
                look = o.present("look")?.let(ProviderLook::from) ?: ProviderLook(),
            )
        }
    }
}

/**
 * The face — an SF Symbol, an icon in the asset catalog, and a colour with the gradient it
 * runs into, for light and dark. Plain data: the app turns it into colours.
 */
internal data class ProviderLook(
    val symbol: String? = null,
    val icon: String? = null,
    val color: Shades? = null,
    /** Where the provider's gradient ends; it starts at `color`. */
    val gradientEnd: Shades? = null,
) {
    /** `[red, green, blue]`, each 0…1, as written in the definition. */
    data class RGB(val red: Double, val green: Double, val blue: Double) {
        fun toJson(): JsonArray = JsonArray(listOf(JsonPrimitive(red), JsonPrimitive(green), JsonPrimitive(blue)))

        companion object {
            fun from(json: JsonElement): RGB {
                val parts = (json as? JsonArray)?.map { (it as? JsonPrimitive)?.takeUnless { p -> p.isString }?.doubleOrNull }
                if (parts == null || parts.size < 3 || parts.take(3).any { it == null }) throw DefinitionError("a colour is [red, green, blue]")
                return RGB(parts[0]!!, parts[1]!!, parts[2]!!)
            }
        }
    }

    /** One colour per appearance. */
    data class Shades(val light: RGB, val dark: RGB) {
        fun toJson(): JsonObject = JsonObject(mapOf("light" to light.toJson(), "dark" to dark.toJson()))

        companion object {
            fun from(json: JsonElement): Shades {
                val o = json as? JsonObject ?: throw DefinitionError("a colour's shades are an object")
                return Shades(RGB.from(o["light"] ?: throw DefinitionError("shades need \"light\"")), RGB.from(o["dark"] ?: throw DefinitionError("shades need \"dark\"")))
            }
        }
    }

    fun toJson(): JsonObject = JsonObject(buildMap {
        symbol?.let { put("symbol", JsonPrimitive(it)) }
        icon?.let { put("icon", JsonPrimitive(it)) }
        color?.let { put("color", it.toJson()) }
        gradientEnd?.let { put("gradientEnd", it.toJson()) }
    })

    companion object {
        fun from(json: JsonElement): ProviderLook {
            val o = json as? JsonObject ?: throw DefinitionError("look is an object")
            return ProviderLook(o.string("symbol"), o.string("icon"), o.present("color")?.let(Shades::from), o.present("gradientEnd")?.let(Shades::from))
        }
    }
}

/** A way *Add Account* offers — one per key of a definition's `accounts`. */
internal enum class AddAccountWay {
    /** *Sign in with browser* */
    SIGN_IN,

    /** *Choose Signed-in Folder* */
    FOLDER,

    /** The account's own settings — *Enter API key* */
    FORM,
}

/** The value under [key], unless it is absent or `null` — how an optional part of a definition reads. */
internal fun JsonObject.present(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

/** A map of text, every value text. */
internal fun JsonObject.textMap(key: String): Map<String, String>? = (present(key) as? JsonObject)?.mapValues { (name, value) ->
    (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw DefinitionError("\"$key.$name\" is text")
}

/** The same fetch with the CLI at [binary] wherever it ran [cli]. */
private fun Fetch.runningCLI(cli: String, binary: String): Fetch = when {
    this is Fetch.JsonRpc && call.cli == cli -> Fetch.JsonRpc(call.copy(cli = binary))
    this is Fetch.Cli && call.cli == cli -> Fetch.Cli(call.copy(cli = binary))
    this is Fetch.Command && call.cli == cli -> Fetch.Command(call.copy(cli = binary))
    else -> this
}

/** A credential refresh that runs [cli] repointed at [binary], through the lookups that wrap it. */
private fun CredentialLookup.runningCLI(cli: String, binary: String): CredentialLookup = when (this) {
    is CredentialLookup.FirstOf -> CredentialLookup.FirstOf(lookups.map { it.runningCLI(cli, binary) })
    is CredentialLookup.Refined -> CredentialLookup.Refined(base.runningCLI(cli, binary), refinement)
    is CredentialLookup.Refreshing -> {
        val refresh = refresh
        CredentialLookup.Refreshing(
            base.runningCLI(cli, binary),
            if (refresh is CredentialRefresh.Cli && refresh.call.cli == cli) CredentialRefresh.Cli(refresh.call.copy(cli = binary)) else refresh,
        )
    }
    else -> this
}
