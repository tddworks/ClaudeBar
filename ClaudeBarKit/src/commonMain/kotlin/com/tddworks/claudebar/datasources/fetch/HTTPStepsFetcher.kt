package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.Credential
import com.tddworks.claudebar.datasources.Fetching
import com.tddworks.claudebar.datasources.HTTPRequest
import com.tddworks.claudebar.datasources.HTTPStatusError
import com.tddworks.claudebar.datasources.HTTPStep
import com.tddworks.claudebar.datasources.HTTPSteps
import com.tddworks.claudebar.datasources.JsonPath
import com.tddworks.claudebar.datasources.NetworkClient
import com.tddworks.claudebar.datasources.Response
import com.tddworks.claudebar.diagnostics.AppLog
import com.tddworks.claudebar.quotas.UsageError
import io.ktor.http.decodeURLQueryComponent
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `http.steps` — the requests in order, each filled with the credential and the values
 * earlier steps kept. A kept value never replaces a credential value. The response is every
 * answer, by step name.
 */
internal class HTTPStepsFetcher(
    val steps: HTTPSteps,
    private val network: NetworkClient,
    private val now: () -> Double,
) : Fetching {
    override fun isReady() = true

    override suspend fun fetch(credential: Credential?): Response {
        var values = credential ?: Credential(emptyMap())
        val answers = mutableMapOf<String, JsonElement>()
        var last: Response? = null
        for (step in steps.steps) {
            val known = step.unless
            if (known != null && values[known] != null) {
                AppLog.probes.debug("http step ${step.name}: skipped, $known is known")
                continue
            }
            try {
                val response = send(step, values)
                for ((name, value) in kept(step.keep, response)) if (values[name] == null) values = values.with(name, value)
                answers[step.name] = parsed(response) ?: JsonPrimitive(response.text)
                last = response
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                // A refused key or a rate limit is the whole data source's business:
                // refresh-and-retry, or the remembered wait.
                if (!step.optional || concernsEveryStep(error)) throw error
                AppLog.probes.info("http step ${step.name}: failed, going on without it")
            }
        }
        val answered = last ?: throw UsageError.NoData
        return Response(answered.status, answered.headers, JsonObject(answers.sortedByKey()).toString().encodeToByteArray())
    }

    /** One step, tried again on a network failure or a 5xx. */
    private suspend fun send(step: HTTPStep, values: Credential): Response {
        var filled = values
        for (name in step.dropEmpty) if (filled[name] == null) filled = filled.with(name, "")
        val fetcher = HTTPFetcher(droppingEmpty(step.dropEmpty, step.request, values), network, now)
        var attempt = 1
        while (true) {
            try {
                return fetcher.fetch(filled)
            } catch (error: HTTPStatusError) {
                if (error.status !in 500..599 || attempt >= step.attempts) throw error
            } catch (error: UsageError) {
                if (error.tag != "executionFailed" || attempt >= step.attempts) throw error
            }
            attempt += 1
        }
    }

    companion object {
        private fun concernsEveryStep(error: Exception): Boolean {
            val refused = error as? HTTPStatusError ?: return false
            return refused.reason is UsageError.AuthenticationRequired || refused.reason is UsageError.RateLimited
        }

        private fun parsed(response: Response): JsonElement? = runCatching { Json.parseToJsonElement(response.text) }.getOrNull()

        /**
         * The request with what came out empty left out: a JSON body key, a URL query item, or
         * a header, filled with one of [names] that has no value.
         */
        fun droppingEmpty(names: List<String>, request: HTTPRequest, values: Credential): HTTPRequest {
            val missing = names.filter { values[it] == null }.toSet()
            if (missing.isEmpty()) return request
            fun isMissing(template: String?): Boolean {
                if (template == null || !template.startsWith("{{") || !template.endsWith("}}") || template.length < 4) return false
                return template.substring(2, template.length - 2).trim() in missing
            }

            val url = request.url.let { url ->
                val start = url.indexOf('?').takeIf { it >= 0 } ?: return@let url
                val end = url.indexOf('#', start).takeIf { it >= 0 } ?: url.length
                val items = url.substring(start + 1, end).split('&').filter { it.isNotEmpty() }
                val kept = items.filterNot { item ->
                    val value = item.substringAfter('=', "")
                    isMissing(value) || isMissing(runCatching { value.decodeURLQueryComponent() }.getOrNull())
                }
                url.substring(0, start + 1) + kept.joinToString("&") + url.substring(end)
            }
            val body = request.body?.let { text ->
                val json = runCatching { Json.parseToJsonElement(text) }.getOrNull() as? JsonObject ?: return@let text
                val kept = json.filterValues { value -> !isMissing((value as? JsonPrimitive)?.takeIf { it.isString }?.content) }
                JsonObject(kept.sortedByKey()).toString()
            }
            val headers = request.headers.filterValues { !isMissing(it) }
            return request.copy(url = url, headers = headers, body = body)
        }

        /** The values a step keeps from its response; one that is absent is left out. */
        fun kept(keep: Map<String, HTTPStep.Keep>, response: Response): Map<String, String> {
            val json = parsed(response)
            val values = mutableMapOf<String, String>()
            for ((name, rule) in keep) {
                when (rule) {
                    is HTTPStep.Keep.Paths -> rule.paths.asSequence()
                        .mapNotNull { JsonPath.string(JsonPath.walk(json, JsonPath.components(it))) }
                        .firstOrNull { it.isNotEmpty() }
                        ?.let { values[name] = it }
                    is HTTPStep.Keep.Pattern -> runCatching { Regex(rule.pattern) }.getOrNull()
                        ?.find(response.text)?.groups?.get(1)?.value
                        ?.let { values[name] = it }
                }
            }
            return values
        }
    }
}

/** Keys in order, so the body reads the same every time. */
private fun <V> Map<String, V>.sortedByKey(): Map<String, V> = entries.sortedBy { it.key }.associate { it.key to it.value }
