package com.tddworks.claudebar.leaderboard

/**
 * *PROFILE LINK* — one place on X, Instagram or GitHub where people on the board can find a
 * member. Only a handle is held; the address is always the platform's own, so a link can't point
 * anywhere else. Handles follow each platform's username rules, pinned by `vectors.json`, which
 * the server checks too. Not verified: anyone can type any handle.
 */
@ConsistentCopyVisibility
internal data class ProfileLink private constructor(val platform: Platform, val handle: String) {
    enum class Platform(val rawValue: String, val displayName: String, val prefix: String, val rule: String, pattern: String) {
        X("x", "X", "x.com/", "1–15 letters, numbers or _", """^[A-Za-z0-9_]{1,15}$"""),
        INSTAGRAM(
            "instagram", "Instagram", "instagram.com/", "1–30 letters, numbers, . or _",
            """^(?!\.)(?!.*\.\.)(?!.*\.$)[A-Za-z0-9._]{1,30}$""",
        ),
        GITHUB(
            "github", "GitHub", "github.com/", "1–39 letters, numbers or single -",
            """^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$""",
        ),
        ;

        internal val regex = Regex(pattern)

        companion object {
            fun of(rawValue: String): Platform? = entries.firstOrNull { it.rawValue == rawValue }
        }
    }

    /** The platform's own address and the handle: `https://github.com/octocat`. */
    val url: String get() = "https://" + platform.prefix + handle

    companion object {
        /** A link when `handle` fits the platform's rules exactly, as the server checks them. */
        fun of(platform: Platform, handle: String): ProfileLink? =
            if (platform.regex.containsMatchIn(handle)) ProfileLink(platform, handle) else null

        /** What someone typed into a handle field, as a link: spaces and a leading `@` aren't part of a handle. */
        fun typed(text: String, platform: Platform): ProfileLink? {
            val trimmed = text.trim { it == '\t' || it.category == CharCategory.SPACE_SEPARATOR }
            return of(platform, trimmed.removePrefix("@"))
        }
    }
}
