package com.tddworks.claudebar.datasources.lookup

import com.tddworks.claudebar.datasources.BrowserCookie
import com.tddworks.claudebar.datasources.BrowserCookieReading
import com.tddworks.claudebar.datasources.BrowserStorageReading
import com.tddworks.claudebar.datasources.CLIExecutor
import com.tddworks.claudebar.datasources.CLIResult
import com.tddworks.claudebar.datasources.HttpCall
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.datasources.SecretStore
import kotlinx.serialization.json.Json
import java.io.File
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/** Hand-written fakes for the lookup's ports. */

internal fun lookup(json: String): CredentialLookup = CredentialLookup.from(Json.parseToJsonElement(json))

/** Answers every request with [answer], keeping each one sent. */
internal class FakeNetwork(private val answer: (HttpCall) -> Response = { Response(status = 200, body = ByteArray(0)) }) : NetworkClient {
    val sent = mutableListOf<HttpCall>()

    override suspend fun send(call: HttpCall): Response {
        sent += call
        return answer(call)
    }
}

/** A CLI that is installed or not; running it does [run]. */
internal class FakeCLI(private val located: Boolean = true, private val run: () -> Unit = {}) : CLIExecutor {
    val inputs = mutableListOf<String?>()

    override fun locate(binary: String): String? = if (located) "/usr/local/bin/$binary" else null

    override suspend fun execute(
        binary: String, args: List<String>, input: String?, timeoutSeconds: Double,
        workingDirectory: String?, autoResponses: Map<String, String>,
    ): CLIResult {
        inputs += input
        run()
        return CLIResult("")
    }
}

/** Every `security` invocation, in order, each answered by [answer]. */
internal class FakeSecurity(private val answer: (List<String>) -> SecurityResult) : SecurityTool {
    val calls = mutableListOf<List<String>>()

    override fun run(arguments: List<String>): SecurityResult {
        calls += arguments
        return answer(arguments)
    }
}

/** A vault in memory, keyed by `provider.name`. */
internal class FakeVault(private val secrets: Map<String, String> = emptyMap()) : SecretStore {
    override fun secret(name: String, provider: String): String? = secrets["$provider.$name"]
}

/** A database whose rows depend on what the file holds — so a copy answers as its original does. */
internal class FakeDatabase(private val rows: (contents: String, query: String) -> List<Map<String, StoredValue>>) : SQLiteReading {
    val queries = mutableListOf<String>()

    override fun rows(path: String, query: String, name: String, limit: Int): List<Map<String, StoredValue>> {
        queries += query
        return rows(File(path).readText(), query).take(limit)
    }
}

internal class FakeKeychain(private val passwords: Map<SafeStorageLabel, String>) : SafeStorageKeychain {
    val asked = mutableListOf<SafeStorageLabel>()

    override fun password(service: String, account: String): String? {
        asked += SafeStorageLabel(service, account)
        return passwords[SafeStorageLabel(service, account)]
    }
}

/** The JDK's PBKDF2 and AES — the same primitives CommonCrypto gives the Mac. */
internal object JdkCrypto : CookieCrypto {
    override fun pbkdf2Sha1(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray =
        SecretKeyFactory.getInstance("PBKDF2WithHmacSHA1")
            .generateSecret(PBEKeySpec(password.decodeToString().toCharArray(), salt, iterations, length * 8)).encoded

    override fun aes128CbcDecrypt(data: ByteArray, key: ByteArray, iv: ByteArray): ByteArray? = runCatching {
        Cipher.getInstance("AES/CBC/PKCS5Padding").apply { init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv)) }.doFinal(data)
    }.getOrNull()

    /** What Chromium stores: `v10` + AES-128-CBC of [plain] under the key [password] derives. */
    fun encrypt(plain: ByteArray, password: String): ByteArray {
        val key = pbkdf2Sha1(password.encodeToByteArray(), "saltysalt".encodeToByteArray(), 1003, 16)
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            .apply { init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(ByteArray(16) { 0x20 })) }
        return "v10".encodeToByteArray() + cipher.doFinal(plain)
    }
}

internal fun text(value: String) = StoredValue.Text(value)

/** Cookie stores that answer [stores] for the domains and names asked, nothing for any other. */
internal class FakeCookies(
    private val stores: List<List<BrowserCookie>> = emptyList(),
    private val domains: List<String>? = null,
    private val names: List<String>? = null,
) : BrowserCookieReading {
    override fun stores(domains: List<String>, names: List<String>): List<List<BrowserCookie>> =
        if ((this.domains == null || this.domains == domains) && (this.names == null || this.names == names)) stores else emptyList()
}

/** Local storage that answers [stores] for [origin] (any, when null). */
internal class FakeStorage(private val stores: List<Map<String, String>> = emptyList(), private val origin: String? = null) : BrowserStorageReading {
    override fun stores(origin: String): List<Map<String, String>> = if (this.origin == null || this.origin == origin) stores else emptyList()
}

/** What [block] threw, asserted to be a [T]. */
internal suspend inline fun <reified T : Throwable> failure(block: suspend () -> Unit): T {
    val error = try {
        block()
        null
    } catch (thrown: Throwable) {
        thrown
    }
    return error as? T ?: throw AssertionError("expected ${T::class.simpleName}, got $error")
}
