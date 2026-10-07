package com.tddworks.claudebar.datasources.fetch.aws

import kotlinx.io.buffered
import kotlinx.io.files.Path
import kotlinx.io.files.SystemFileSystem
import kotlinx.io.readString

/** Why no AWS credentials were found — never carrying one. */
internal class AWSCredentialsError(message: String) : Exception(message)

/**
 * The person's own AWS credentials, found the way the AWS SDK finds static ones:
 *
 * - **no profile** — `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` (+ `AWS_SESSION_TOKEN`),
 *   else the profile `AWS_PROFILE` names, else `default`;
 * - **a named profile** — that profile only, never the environment's keys.
 *
 * A profile is read from `~/.aws/credentials` (`[name]`) and `~/.aws/config` (`[profile name]`,
 * `[default]`), or the files `AWS_SHARED_CREDENTIALS_FILE` and `AWS_CONFIG_FILE` name; the
 * credentials file wins a key both set. Only keys written in the profile are used: SSO, an
 * assumed role, `credential_process`, web identity and the container or instance metadata
 * services are not resolved, and a profile that needs one fails saying so.
 */
internal class AWSCredentialResolver(
    private val home: String,
    private val environment: (String) -> String?,
) {
    fun resolve(profile: String?): AWSCredentials {
        if (profile == null) {
            val key = environment("AWS_ACCESS_KEY_ID")?.takeIf { it.isNotEmpty() }
            val secret = environment("AWS_SECRET_ACCESS_KEY")?.takeIf { it.isNotEmpty() }
            if (key != null && secret != null) {
                return AWSCredentials(key, secret, environment("AWS_SESSION_TOKEN")?.takeIf { it.isNotEmpty() })
            }
        }
        val name = profile ?: environment("AWS_PROFILE")?.takeIf { it.isNotEmpty() } ?: "default"
        val values = profileValues(name) ?: throw AWSCredentialsError("No AWS profile \"$name\" in the credentials or config file")
        val key = values["aws_access_key_id"]?.takeIf { it.isNotEmpty() }
        val secret = values["aws_secret_access_key"]?.takeIf { it.isNotEmpty() }
        if (key != null && secret != null) return AWSCredentials(key, secret, values["aws_session_token"]?.takeIf { it.isNotEmpty() })
        val needs = UNSUPPORTED.firstOrNull { (setting, _) -> values.containsKey(setting) }?.second
        throw AWSCredentialsError(
            if (needs != null) "AWS profile \"$name\" uses $needs, which ClaudeBar can't sign in with yet; give it an access key"
            else "AWS profile \"$name\" has no access key",
        )
    }

    /** The profile's settings, the credentials file over the config file; null when neither names it. */
    private fun profileValues(name: String): Map<String, String>? {
        val config = read(environment("AWS_CONFIG_FILE") ?: "~/.aws/config")?.let(AWSProfileFile::sections)
            ?.let { sections -> sections["profile $name"] ?: if (name == "default") sections["default"] else null }
        val credentials = read(environment("AWS_SHARED_CREDENTIALS_FILE") ?: "~/.aws/credentials")
            ?.let(AWSProfileFile::sections)?.get(name)
        if (config == null && credentials == null) return null
        return config.orEmpty() + credentials.orEmpty()
    }

    private fun read(path: String): String? {
        val expanded = if (path == "~" || path.startsWith("~/")) home.trimEnd('/') + path.removePrefix("~") else path
        return runCatching { SystemFileSystem.source(Path(expanded)).buffered().use { it.readString() } }.getOrNull()
    }

    private companion object {
        val UNSUPPORTED = listOf(
            "sso_session" to "SSO",
            "sso_start_url" to "SSO",
            "role_arn" to "an assumed role",
            "credential_process" to "a credential process",
            "web_identity_token_file" to "a web identity",
            "credential_source" to "a credential source",
        )
    }
}

/** The INI dialect of `~/.aws/config` and `~/.aws/credentials`. */
internal object AWSProfileFile {
    /** Section name → its keys, lowercased; indented sub-settings (`s3 =` blocks) skipped. */
    fun sections(text: String): Map<String, Map<String, String>> {
        val sections = mutableMapOf<String, MutableMap<String, String>>()
        var current: MutableMap<String, String>? = null
        for (raw in text.lines()) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#") || line.startsWith(";")) continue
            if (line.startsWith("[")) {
                val name = line.removePrefix("[").substringBefore("]").trim().replace(Regex("\\s+"), " ")
                current = sections.getOrPut(name) { mutableMapOf() }
                continue
            }
            if (raw.first().isWhitespace() || '=' !in line) continue
            val key = line.substringBefore('=').trim().lowercase()
            current?.set(key, line.substringAfter('=').trim())
        }
        return sections
    }
}
