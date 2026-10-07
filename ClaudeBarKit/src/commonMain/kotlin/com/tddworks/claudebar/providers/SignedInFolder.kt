package com.tddworks.claudebar.providers

import kotlinx.io.files.Path
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/**
 * *Signed-in Folder* — where an added login lives: the folder its CLI keeps its key in, and who
 * made it. A folder the person chose is theirs; one ClaudeBar made for *Sign in with browser*
 * is ClaudeBar's, and goes with the account (docs/features/in-use/design.md).
 */
@ConsistentCopyVisibility
public data class SignedInFolder private constructor(val path: String, val madeBy: AccountOrigin) {
    /**
     * Whether *Remove* takes the folder with the account: only one ClaudeBar made by signing in,
     * named as it names them. A live refresh token left behind would be a login nobody can see.
     */
    val goesWithAccount: Boolean get() = madeBy == AccountOrigin.SIGN_IN && uuid.matches(path.substringAfterLast('/'))

    companion object {
        private val uuid = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

        /** The folder, written one way: no `.` or `..` parts, no trailing slash. */
        operator fun invoke(path: String, madeBy: AccountOrigin) = SignedInFolder(standardized(path), madeBy)

        /** Where *Sign in with browser* makes its folders: `<provider>/<uuid>`. */
        fun signInRoot(home: String): String = Path(home, ".claudebar", "accounts").toString()

        /** A new folder for one sign-in to [providerId]. */
        @OptIn(ExperimentalUuidApi::class)
        fun forSignIn(providerId: String, root: String): SignedInFolder =
            SignedInFolder(Path(root, providerId, Uuid.random().toString().lowercase()).toString(), AccountOrigin.SIGN_IN)

        private fun standardized(path: String): String {
            val absolute = path.startsWith("/")
            val parts = mutableListOf<String>()
            for (part in path.split('/')) {
                when {
                    part.isEmpty() || part == "." -> Unit
                    part == ".." && parts.isNotEmpty() && parts.last() != ".." -> parts.removeAt(parts.lastIndex)
                    part == ".." && absolute -> Unit
                    else -> parts += part
                }
            }
            val joined = parts.joinToString("/")
            return if (absolute) "/$joined" else joined
        }
    }
}
