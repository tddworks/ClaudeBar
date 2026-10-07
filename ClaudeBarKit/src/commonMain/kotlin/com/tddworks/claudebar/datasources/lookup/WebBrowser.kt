package com.tddworks.claudebar.datasources.lookup

/** How a browser keeps its cookies on disk. */
internal enum class BrowserEngine { WEBKIT, CHROMIUM, GECKO }

/** The Keychain item holding a Chromium browser's cookie password: `"Chrome Safe Storage"`, account `"Chrome"`. */
internal data class SafeStorageLabel(val service: String, val account: String)

/**
 * The browsers whose cookies and local storage ClaudeBar reads, in the order it asks them — the
 * order SweetCookieKit's `Browser.defaultImportOrder` gave the Swift app.
 */
internal enum class WebBrowser(
    val displayName: String,
    val engine: BrowserEngine,
    /** The profiles' root under `~/Library/Application Support`, for a Chromium browser. */
    val profileRoot: String? = null,
    /** The `Profiles` folder's parent under `~/Library/Application Support`, for a Gecko browser. */
    val geckoFolder: String? = null,
    val safeStorageLabels: List<SafeStorageLabel> = emptyList(),
) {
    SAFARI("Safari", BrowserEngine.WEBKIT),
    CHROME("Chrome", BrowserEngine.CHROMIUM, "Google/Chrome", safeStorageLabels = labels("Chrome Safe Storage" to "Chrome")),
    EDGE("Microsoft Edge", BrowserEngine.CHROMIUM, "Microsoft Edge", safeStorageLabels = labels("Microsoft Edge Safe Storage" to "Microsoft Edge")),
    BRAVE("Brave", BrowserEngine.CHROMIUM, "BraveSoftware/Brave-Browser", safeStorageLabels = labels("Brave Safe Storage" to "Brave")),
    ARC("Arc", BrowserEngine.CHROMIUM, "Arc/User Data", safeStorageLabels = labels("Arc Safe Storage" to "Arc")),
    DIA("Dia", BrowserEngine.CHROMIUM, "Dia/User Data", safeStorageLabels = labels("Dia Safe Storage" to "Dia")),
    ATLAS(
        "ChatGPT Atlas", BrowserEngine.CHROMIUM, "com.openai.atlas/browser-data/host",
        safeStorageLabels = labels(
            "ChatGPT Atlas Safe Storage" to "ChatGPT Atlas",
            "ChatGPT Atlas Safe Storage" to "com.openai.atlas",
            "com.openai.atlas Safe Storage" to "com.openai.atlas",
        ),
    ),
    CHROMIUM("Chromium", BrowserEngine.CHROMIUM, "Chromium", safeStorageLabels = labels("Chromium Safe Storage" to "Chromium")),
    HELIUM(
        "Helium", BrowserEngine.CHROMIUM, "net.imput.helium",
        safeStorageLabels = labels("Helium Safe Storage" to "Helium", "net.imput.helium Safe Storage" to "net.imput.helium"),
    ),
    VIVALDI("Vivaldi", BrowserEngine.CHROMIUM, "Vivaldi", safeStorageLabels = labels("Vivaldi Safe Storage" to "Vivaldi")),
    FIREFOX("Firefox", BrowserEngine.GECKO, geckoFolder = "Firefox"),
    ZEN("Zen", BrowserEngine.GECKO, geckoFolder = "zen"),
    CHROME_BETA("Chrome Beta", BrowserEngine.CHROMIUM, "Google/Chrome Beta"),
    CHROME_CANARY("Chrome Canary", BrowserEngine.CHROMIUM, "Google/Chrome Canary"),
    ARC_BETA("Arc Beta", BrowserEngine.CHROMIUM, "Arc Beta/User Data", safeStorageLabels = labels("Arc Safe Storage" to "Arc Beta")),
    ARC_CANARY("Arc Canary", BrowserEngine.CHROMIUM, "Arc Canary/User Data", safeStorageLabels = labels("Arc Safe Storage" to "Arc Canary")),
    BRAVE_BETA("Brave Beta", BrowserEngine.CHROMIUM, "BraveSoftware/Brave-Browser-Beta"),
    BRAVE_NIGHTLY("Brave Nightly", BrowserEngine.CHROMIUM, "BraveSoftware/Brave-Browser-Nightly"),
    EDGE_BETA("Microsoft Edge Beta", BrowserEngine.CHROMIUM, "Microsoft Edge Beta"),
    EDGE_CANARY("Microsoft Edge Canary", BrowserEngine.CHROMIUM, "Microsoft Edge Canary"),
    ;

    /**
     * The Keychain items to try for this browser's cookie password: its own first, then every
     * browser's in SweetCookieKit's order — a beta or canary build has no item of its own and
     * shares its stable sibling's.
     */
    val passwordLabels: List<SafeStorageLabel>
        get() = (safeStorageLabels + sharedLabelOrder.flatMap { it.safeStorageLabels }).distinct()

    companion object {
        /** The order the Swift app asked the browsers in. */
        val importOrder: List<WebBrowser> = entries

        private val sharedLabelOrder = listOf(CHROME, CHROMIUM, BRAVE, ARC, ARC_BETA, ARC_CANARY, ATLAS, HELIUM, EDGE, VIVALDI, DIA)
    }
}

private fun labels(vararg pairs: Pair<String, String>) = pairs.map { SafeStorageLabel(it.first, it.second) }
