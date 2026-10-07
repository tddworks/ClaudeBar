package com.tddworks.claudebar.datasources.fetch.aws

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File

/** The person's own AWS keys: the environment's, or a profile's in `~/.aws`. */
class AWSCredentialResolverTest {
    @TempDir
    lateinit var home: File

    private fun aws(file: String, text: String) = File(home, ".aws/$file").apply { parentFile.mkdirs(); writeText(text) }

    private fun resolver(environment: Map<String, String> = emptyMap()) = AWSCredentialResolver(home.path) { environment[it] }

    private val environmentKeys = mapOf("AWS_ACCESS_KEY_ID" to "env-key", "AWS_SECRET_ACCESS_KEY" to "env-secret", "AWS_SESSION_TOKEN" to "env-token")

    @Test
    fun `should use the environment's keys when no profile is chosen`() {
        aws("credentials", "[default]\naws_access_key_id = file-key\naws_secret_access_key = file-secret\n")
        assertEquals(AWSCredentials("env-key", "env-secret", "env-token"), resolver(environmentKeys).resolve(null))
    }

    @Test
    fun `should use the chosen profile, never the environment's keys`() {
        aws("credentials", "[work]\naws_access_key_id = work-key\naws_secret_access_key = work-secret\n")
        assertEquals(AWSCredentials("work-key", "work-secret"), resolver(environmentKeys).resolve("work"))
    }

    @Test
    fun `should use the profile AWS_PROFILE names, else the default one, when no profile is chosen`() {
        aws("credentials", "[default]\naws_access_key_id = d\naws_secret_access_key = ds\n[dev]\naws_access_key_id = v\naws_secret_access_key = vs\n")
        assertEquals("v", resolver(mapOf("AWS_PROFILE" to "dev")).resolve(null).accessKeyId)
        assertEquals("d", resolver().resolve(null).accessKeyId)
    }

    @Test
    fun `should read a profile from the config file, the credentials file winning a key both set`() {
        aws("config", "# mine\n[default]\nregion = us-east-1\n[profile work]\naws_access_key_id = config-key\n" +
            "aws_secret_access_key = config-secret\naws_session_token = t\ns3 =\n  max_concurrent_requests = 2\n")
        aws("credentials", "[work]\naws_secret_access_key = credentials-secret\n")

        assertEquals(AWSCredentials("config-key", "credentials-secret", "t"), resolver().resolve("work"))
    }

    @Test
    fun `should say a profile needs SSO when it signs in that way`() {
        aws("config", "[profile corp]\nsso_session = corp\nsso_account_id = 1\nsso_role_name = dev\n")

        val error = assertThrows<AWSCredentialsError> { resolver().resolve("corp") }

        assertTrue("SSO" in error.message.orEmpty(), error.message)
    }

    @Test
    fun `should find no credentials when there is no key and no profile file`() {
        assertThrows<AWSCredentialsError> { resolver().resolve(null) }
    }
}
