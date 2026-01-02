package com.tddworks.claudebar.infrastructure.probes.antigravity

import com.tddworks.claudebar.domain.model.AccountTier
import com.tddworks.claudebar.domain.model.ProbeError
import com.tddworks.claudebar.domain.model.QuotaType
import com.tddworks.claudebar.domain.model.UsageQuota
import com.tddworks.claudebar.domain.model.UsageSnapshot
import com.tddworks.claudebar.domain.provider.UsageProbe
import com.tddworks.claudebar.infrastructure.cli.CLIExecutor
import com.tddworks.claudebar.infrastructure.network.NetworkClient
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

/**
 * Probes the local Antigravity language server for usage quota information.
 * Antigravity runs as a local process and exposes quota data via a local API.
 */
class AntigravityUsageProbe(
    private val cliExecutor: CLIExecutor,
    private val networkClient: NetworkClient,
    private val timeout: Duration = 8.seconds,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : UsageProbe {

    companion object {
        private val PROCESS_NAMES = listOf("language_server_macos", "language_server_macos_arm")
        private val API_PATHS = listOf(
            "/exa.language_server_pb.LanguageServerService/GetUserStatus",
            "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
        )
    }

    override suspend fun isAvailable(): Boolean {
        return try {
            detectProcess() != null
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun probe(): UsageSnapshot {
        // Step 1: Detect running Antigravity process
        val processInfo = detectProcess()
            ?: throw ProbeError.CliNotFound("Antigravity")

        // Step 2: Find listening ports
        val ports = discoverPorts(processInfo.pid)
        if (ports.isEmpty()) {
            throw ProbeError.ExecutionFailed("No listening ports found for Antigravity")
        }

        // Step 3: Find working port and fetch quota
        val responseBody = fetchQuota(ports, processInfo.csrfToken, processInfo.extensionPort)
            ?: throw ProbeError.ExecutionFailed("Could not connect to Antigravity API")

        // Step 4: Parse response
        return parseUserStatusResponse(responseBody)
    }

    // MARK: - Process Detection

    private data class ProcessInfo(
        val pid: Int,
        val csrfToken: String,
        val extensionPort: Int?
    )

    private suspend fun detectProcess(): ProcessInfo? {
        val result = cliExecutor.execute(
            binary = "/usr/bin/pgrep",
            args = listOf("-lf", "language_server_macos"),
            timeout = timeout
        )

        val lines = result.output
            .replace("\r\n", "\n")
            .replace("\r", "\n")
            .split("\n")
            .filter { it.isNotBlank() }

        for (line in lines) {
            val trimmed = line.trim()
            if (!isAntigravityProcess(trimmed)) continue

            val pid = extractPID(trimmed) ?: continue
            val csrfToken = extractCSRFToken(trimmed)

            if (csrfToken != null) {
                val extensionPort = extractExtensionPort(trimmed)
                return ProcessInfo(pid, csrfToken, extensionPort)
            }
        }

        return null
    }

    // MARK: - Port Discovery

    private suspend fun discoverPorts(pid: Int): List<Int> {
        val result = cliExecutor.execute(
            binary = "/usr/sbin/lsof",
            args = listOf("-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pid.toString()),
            timeout = timeout
        )

        return parseListeningPorts(result.output)
    }

    // MARK: - API Calls

    private suspend fun fetchQuota(ports: List<Int>, csrfToken: String, httpPort: Int?): String? {
        val headers = mapOf(
            "Content-Type" to "application/json",
            "X-Codeium-Csrf-Token" to csrfToken,
            "Connect-Protocol-Version" to "1"
        )

        val body = """{"metadata":{"ideName":"antigravity","extensionName":"antigravity","ideVersion":"unknown","locale":"en"}}"""

        // Try HTTPS ports first
        for (port in ports) {
            for (path in API_PATHS) {
                try {
                    val response = networkClient.post(
                        url = "https://127.0.0.1:$port$path",
                        body = body,
                        headers = headers
                    )
                    if (response.statusCode == 200) {
                        return response.body
                    }
                } catch (e: Exception) {
                    // Continue to next port
                }
            }
        }

        // Fallback to HTTP on extension port
        if (httpPort != null) {
            for (path in API_PATHS) {
                try {
                    val response = networkClient.post(
                        url = "http://127.0.0.1:$httpPort$path",
                        body = body,
                        headers = headers
                    )
                    if (response.statusCode == 200) {
                        return response.body
                    }
                } catch (e: Exception) {
                    // Continue
                }
            }
        }

        return null
    }

    // MARK: - Parsing Helpers

    internal fun isAntigravityProcess(commandLine: String): Boolean {
        val lower = commandLine.lowercase()
        if (!PROCESS_NAMES.any { lower.contains(it) }) return false

        // Check for app_data_dir flag with antigravity value
        if (lower.contains("--app_data_dir") && lower.contains("antigravity")) {
            return true
        }
        // Check for antigravity in the path
        if (lower.contains("/antigravity/") || lower.contains(".antigravity/")) {
            return true
        }
        return false
    }

    internal fun extractPID(line: String): Int? {
        val parts = line.trim().split(" ", limit = 2)
        return parts.firstOrNull()?.toIntOrNull()
    }

    internal fun extractCSRFToken(commandLine: String): String? {
        return extractFlag("--csrf_token", commandLine)
    }

    internal fun extractExtensionPort(commandLine: String): Int? {
        return extractFlag("--extension_server_port", commandLine)?.toIntOrNull()
    }

    private fun extractFlag(flag: String, command: String): String? {
        val pattern = Regex("""$flag[=\s]+([^\s]+)""", RegexOption.IGNORE_CASE)
        return pattern.find(command)?.groupValues?.getOrNull(1)
    }

    internal fun parseListeningPorts(output: String): List<Int> {
        val pattern = Regex(""":(\d+)\s+\(LISTEN\)""")
        return pattern.findAll(output)
            .mapNotNull { it.groupValues.getOrNull(1)?.toIntOrNull() }
            .distinct()
            .sorted()
            .toList()
    }

    // MARK: - Response Parsing

    internal fun parseUserStatusResponse(responseBody: String): UsageSnapshot {
        val response = try {
            json.decodeFromString<UserStatusResponse>(responseBody)
        } catch (e: Exception) {
            throw ProbeError.ParseFailed("Invalid JSON: ${e.message}")
        }

        val modelConfigs = response.userStatus?.cascadeModelConfigData?.clientModelConfigs ?: emptyList()

        val quotas = modelConfigs.mapNotNull { config ->
            val quotaInfo = config.quotaInfo ?: return@mapNotNull null
            val remainingFraction = quotaInfo.remainingFraction ?: 0.0
            val resetsAt = quotaInfo.resetTime?.let { parseResetTime(it) }

            UsageQuota(
                percentRemaining = remainingFraction * 100,
                quotaType = QuotaType.ModelSpecific(config.label),
                providerId = "antigravity",
                resetsAt = resetsAt
            )
        }

        if (quotas.isEmpty()) {
            throw ProbeError.ParseFailed("No valid model quotas found")
        }

        val accountTier = response.userStatus?.planStatus?.planInfo?.planName?.let {
            AccountTier.Custom(it.uppercase())
        }

        return UsageSnapshot(
            providerId = "antigravity",
            quotas = quotas,
            capturedAt = Clock.System.now(),
            accountEmail = response.userStatus?.email,
            accountTier = accountTier
        )
    }

    private fun parseResetTime(value: String): Instant? {
        // Try epoch seconds
        value.toDoubleOrNull()?.let {
            return Instant.fromEpochSeconds(it.toLong())
        }

        // Try ISO-8601 (basic support)
        return try {
            Instant.parse(value)
        } catch (e: Exception) {
            null
        }
    }
}

// MARK: - Response Models

@Serializable
internal data class UserStatusResponse(
    val userStatus: UserStatus? = null
)

@Serializable
internal data class UserStatus(
    val email: String? = null,
    val cascadeModelConfigData: ModelConfigData? = null,
    val planStatus: PlanStatus? = null
)

@Serializable
internal data class PlanStatus(
    val planInfo: PlanInfo? = null
)

@Serializable
internal data class PlanInfo(
    val planName: String? = null
)

@Serializable
internal data class ModelConfigData(
    val clientModelConfigs: List<ModelConfig>? = null
)

@Serializable
internal data class ModelConfig(
    val label: String,
    val modelOrAlias: ModelAlias? = null,
    val quotaInfo: QuotaInfo? = null
)

@Serializable
internal data class ModelAlias(
    val model: String? = null
)

@Serializable
internal data class QuotaInfo(
    val remainingFraction: Double? = null,
    val resetTime: String? = null
)
