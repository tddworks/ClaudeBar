package com.tddworks.claudebar.infrastructure.probes.zai

import com.tddworks.claudebar.domain.model.ProbeError
import com.tddworks.claudebar.domain.model.QuotaType
import com.tddworks.claudebar.domain.model.UsageQuota
import com.tddworks.claudebar.domain.model.UsageSnapshot
import com.tddworks.claudebar.domain.provider.UsageProbe
import com.tddworks.claudebar.infrastructure.cli.CLIExecutor
import com.tddworks.claudebar.infrastructure.network.NetworkClient
import com.tddworks.claudebar.infrastructure.platform.FileSystem
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Z.ai platform detection
 */
enum class ZaiPlatform(val baseUrl: String) {
    ZAI("https://api.z.ai"),
    ZHIPU("https://open.bigmodel.cn"),
    DEV("https://dev.bigmodel.cn")
}

/**
 * Probes the z.ai GLM Coding Plan for usage quota information.
 * Z.ai works as an API-compatible replacement for Anthropic's API,
 * configured through Claude Code's settings file.
 */
class ZaiUsageProbe(
    private val cliExecutor: CLIExecutor,
    private val networkClient: NetworkClient,
    private val timeout: Duration = 10.seconds,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : UsageProbe {

    companion object {
        private const val CLAUDE_CONFIG_PATH = "/.claude/settings.json"
    }

    override suspend fun isAvailable(): Boolean {
        // Check if Claude CLI is installed
        if (cliExecutor.locate("claude") == null) {
            return false
        }

        // Check if z.ai is configured in Claude settings
        return try {
            val config = readClaudeConfig()
            hasZaiEndpoint(config)
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun probe(): UsageSnapshot {
        // Step 1: Verify Claude CLI is installed
        if (cliExecutor.locate("claude") == null) {
            throw ProbeError.CliNotFound("Claude")
        }

        // Step 2: Read Claude config
        val config = readClaudeConfig()

        // Step 3: Detect platform and extract API key
        val platform = detectPlatform(config)
            ?: throw ProbeError.AuthenticationRequired

        val apiKey = extractAPIKey(config)
            ?: throw ProbeError.AuthenticationRequired

        // Step 4: Make API request
        val url = "${platform.baseUrl}/api/monitor/usage/quota/limit"
        val headers = mapOf(
            "Authorization" to "Bearer $apiKey",
            "Accept-Language" to "en-US,en",
            "Content-Type" to "application/json"
        )

        val response = networkClient.get(url, headers)

        when (response.statusCode) {
            in 200..299 -> {} // Continue
            401, 403 -> throw ProbeError.AuthenticationRequired
            else -> throw ProbeError.ExecutionFailed("API returned HTTP ${response.statusCode}")
        }

        // Step 5: Parse response
        return parseQuotaLimitResponse(response.body)
    }

    // MARK: - Configuration Reading

    private fun readClaudeConfig(): String {
        val configPath = FileSystem.homeDirectory() + CLAUDE_CONFIG_PATH
        return FileSystem.readFile(configPath)
            ?: throw ProbeError.ExecutionFailed("Could not read Claude config")
    }

    // MARK: - Static Parsing Helpers

    internal fun hasZaiEndpoint(config: String): Boolean {
        return detectPlatform(config) != null
    }

    internal fun detectPlatform(config: String): ZaiPlatform? {
        val jsonObject = try {
            json.parseToJsonElement(config).jsonObject
        } catch (e: Exception) {
            return null
        }

        // Check env.ANTHROPIC_BASE_URL format (Claude Code default)
        val env = jsonObject["env"]?.jsonObject
        val baseURL = env?.get("ANTHROPIC_BASE_URL")?.jsonPrimitive?.contentOrNull

        if (baseURL != null) {
            if (baseURL.contains("api.z.ai")) return ZaiPlatform.ZAI
            if (baseURL.contains("open.bigmodel.cn")) return ZaiPlatform.ZHIPU
            if (baseURL.contains("dev.bigmodel.cn")) return ZaiPlatform.DEV
        }

        // Check providers array format
        val providers = jsonObject["providers"]?.jsonArray
        providers?.forEach { provider ->
            val providerObj = provider.jsonObject
            val providerBaseUrl = providerObj["base_url"]?.jsonPrimitive?.contentOrNull
            if (providerBaseUrl != null) {
                if (providerBaseUrl.contains("api.z.ai")) return ZaiPlatform.ZAI
                if (providerBaseUrl.contains("open.bigmodel.cn")) return ZaiPlatform.ZHIPU
                if (providerBaseUrl.contains("dev.bigmodel.cn")) return ZaiPlatform.DEV
            }
        }

        // Fallback: check for any key with z.ai URL
        val configLower = config.lowercase()
        if (configLower.contains("api.z.ai")) return ZaiPlatform.ZAI
        if (configLower.contains("open.bigmodel.cn")) return ZaiPlatform.ZHIPU
        if (configLower.contains("dev.bigmodel.cn")) return ZaiPlatform.DEV

        return null
    }

    internal fun extractAPIKey(config: String): String? {
        val jsonObject = try {
            json.parseToJsonElement(config).jsonObject
        } catch (e: Exception) {
            return null
        }

        // Check env.ANTHROPIC_AUTH_TOKEN format (Claude Code default)
        val env = jsonObject["env"]?.jsonObject
        val authToken = env?.get("ANTHROPIC_AUTH_TOKEN")?.jsonPrimitive?.contentOrNull
        if (!authToken.isNullOrEmpty()) {
            return authToken
        }

        // Check providers array for api_key
        val providers = jsonObject["providers"]?.jsonArray
        providers?.forEach { provider ->
            val providerObj = provider.jsonObject
            val apiKey = providerObj["api_key"]?.jsonPrimitive?.contentOrNull
            if (!apiKey.isNullOrEmpty()) {
                return apiKey
            }
        }

        // Check for direct api_key field
        val directApiKey = jsonObject["api_key"]?.jsonPrimitive?.contentOrNull
        if (!directApiKey.isNullOrEmpty()) {
            return directApiKey
        }

        return null
    }

    // MARK: - Response Parsing

    internal fun parseQuotaLimitResponse(responseBody: String): UsageSnapshot {
        val response = try {
            json.decodeFromString<QuotaLimitResponse>(responseBody)
        } catch (e: Exception) {
            throw ProbeError.ParseFailed("Invalid JSON: ${e.message}")
        }

        val limits = response.data?.limits
        if (limits.isNullOrEmpty()) {
            throw ProbeError.ParseFailed("No quota limits found")
        }

        val quotas = limits.mapNotNull { limit ->
            val quotaType = when (limit.type) {
                "TOKENS_LIMIT" -> QuotaType.Session
                "TIME_LIMIT" -> QuotaType.TimeLimit("MCP")
                else -> return@mapNotNull null
            }

            val clampedUsed = limit.percentage.coerceIn(0.0, 100.0)
            val percentRemaining = 100.0 - clampedUsed
            val resetsAt = parseResetDate(limit.nextResetTime)

            UsageQuota(
                percentRemaining = percentRemaining,
                quotaType = quotaType,
                providerId = "zai",
                resetsAt = resetsAt
            )
        }

        if (quotas.isEmpty()) {
            throw ProbeError.ParseFailed("No recognized quota types found")
        }

        return UsageSnapshot(
            providerId = "zai",
            quotas = quotas,
            capturedAt = Clock.System.now()
        )
    }

    internal fun parseResetDate(value: FlexibleDate?): Instant? {
        return when (value) {
            is FlexibleDate.Timestamp -> Instant.fromEpochMilliseconds(value.ms)
            is FlexibleDate.StringDate -> {
                // Try epoch seconds
                value.text.toDoubleOrNull()?.let {
                    return Instant.fromEpochSeconds(it.toLong())
                }
                // Try ISO-8601
                try {
                    Instant.parse(value.text)
                } catch (e: Exception) {
                    null
                }
            }
            null -> null
        }
    }
}

// MARK: - Response Models

@Serializable
internal data class QuotaLimitResponse(
    val data: QuotaLimitData? = null
)

@Serializable
internal data class QuotaLimitData(
    val limits: List<QuotaLimit>? = null
)

@Serializable
internal data class QuotaLimit(
    val type: String,
    val percentage: Double,
    val nextResetTime: FlexibleDate? = null
)

/**
 * A type that can be decoded from either a number (timestamp) or a string (ISO date)
 */
@Serializable(with = FlexibleDateSerializer::class)
internal sealed class FlexibleDate {
    data class Timestamp(val ms: Long) : FlexibleDate()
    data class StringDate(val text: String) : FlexibleDate()
}

internal object FlexibleDateSerializer : kotlinx.serialization.KSerializer<FlexibleDate> {
    override val descriptor = kotlinx.serialization.descriptors.PrimitiveSerialDescriptor(
        "FlexibleDate",
        kotlinx.serialization.descriptors.PrimitiveKind.STRING
    )

    override fun serialize(encoder: kotlinx.serialization.encoding.Encoder, value: FlexibleDate) {
        when (value) {
            is FlexibleDate.Timestamp -> encoder.encodeLong(value.ms)
            is FlexibleDate.StringDate -> encoder.encodeString(value.text)
        }
    }

    override fun deserialize(decoder: kotlinx.serialization.encoding.Decoder): FlexibleDate {
        val jsonDecoder = decoder as? kotlinx.serialization.json.JsonDecoder
            ?: return FlexibleDate.StringDate(decoder.decodeString())

        val element = jsonDecoder.decodeJsonElement()
        return when {
            element is JsonPrimitive && element.longOrNull != null -> {
                FlexibleDate.Timestamp(element.longOrNull!!)
            }
            element is JsonPrimitive -> {
                FlexibleDate.StringDate(element.content)
            }
            else -> FlexibleDate.StringDate("")
        }
    }
}
