package com.tddworks.claudebar.datasources

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * `{{system.x}}` — values the engine computes from the fetch's `now` (ENGINE_DESIGN §2.9) —
 * and the credential values a request is filled with.
 */
class TemplateTest {
    /** 2026-10-05 14:30:00 UTC. */
    private val system = SystemValues(nowSeconds = 1_791_210_600.0, timeZone = "Asia/Shanghai", osVersion = "27.1.0")

    @Test
    fun `should send the Mac's time zone even without a credential`() {
        assertEquals("tz=Asia/Shanghai", Template.fill("tz={{system.timeZone}}", null, system))
    }

    @Test
    fun `should send the Mac's version`() {
        assertEquals("27.1.0", Template.fill("{{system.osVersion}}", null, system))
    }

    @Test
    fun `should send now as epoch seconds or ISO 8601`() {
        assertEquals("1791210600", Template.fill("{{system.now.epoch}}", null, system))
        assertEquals("2026-10-05T14:30:00Z", Template.fill("{{system.now.iso8601}}", null, system))
    }

    @Test
    fun `should send the start of a day N days away, at UTC midnight`() {
        assertEquals("1788652800", Template.fill("{{system.day-29.epoch}}", null, system))
        assertEquals("2026-09-06", Template.fill("{{system.day-29.date}}", null, system))
        assertEquals("2026-10-06T00:00:00Z", Template.fill("{{system.day+1.iso8601}}", null, system))
        assertEquals("2026-10-05", Template.fill("{{system.day.date}}", null, system))
    }

    @ParameterizedTest
    @ValueSource(strings = ["system.day-x.epoch", "system.now.week", "system.unknown", "system.day-29"])
    fun `should leave a request unfilled when it names a value the engine doesn't compute`(name: String) {
        assertNull(Template.fill("{{$name}}", null, system))
    }

    @Test
    fun `should not take a system value from the credential`() {
        val credential = Credential(mapOf("system.now.epoch" to "forged", "token" to "t"))
        assertEquals("1791210600/t", Template.fill("{{system.now.epoch}}/{{token}}", credential, system))
    }

    @Test
    fun `should leave a request unfilled when the credential lacks a value`() {
        assertNull(Template.fill("Bearer {{token}}", Credential(emptyMap())))
    }

    @Test
    fun `should send only the host of a credential's address`() {
        assertEquals("api.example.com", Template.fill("{{baseURL#host}}", Credential(mapOf("baseURL" to "https://api.example.com:8443/v1"))))
    }

    @OptIn(ExperimentalEncodingApi::class)
    @Test
    fun `should read a claim out of a token's payload without verifying it`() {
        val payload = Base64.UrlSafe.encode("""{"email":"a@b.c","n":{"id":7}}""".encodeToByteArray()).trimEnd('=')
        val token = "h.$payload.s"
        assertEquals("a@b.c", Template.fill("{{idToken#jwt.email}}", Credential(mapOf("idToken" to token))))
        assertEquals("7", Jwt.claim("n.id", token))
        assertNull(Jwt.claim("email", "not-a-jwt"))
    }

    @Test
    fun `should read paths, headers and numbers the way definitions write them`() {
        val document = kotlinx.serialization.json.Json.parseToJsonElement(
            """{"a":{"b":[{"v":"12.5"},{"v":3}]},"ok":true,"whole":1.0,"gone":null}""",
        )
        val scope = JsonScope(document, headers = mapOf("x-left" to "9"), credential = mapOf("email" to "e@x"))
        assertEquals(12.5, scope.number("$.a.b.0.v"))
        assertEquals("3", scope.string("$.a.b.1.v"))
        assertEquals("1", scope.string("$.ok"))
        assertNull(scope.number("$.ok"))
        assertEquals("1", scope.string("$.whole"))
        assertNull(scope.value("$.gone"))
        assertEquals("9", scope.string("\$header.X-Left"))
        assertEquals("e@x", scope.string("\$credential.email"))
        assertEquals(3.0, scope.moved(to = JsonPath.walk(document, listOf("a", "b", "1"))).number("v"))
    }

    @Test
    fun `should merge a patch the way RFC 7396 says`() {
        val base = kotlinx.serialization.json.Json.parseToJsonElement("""{"a":1,"b":{"c":2,"d":3}}""")
        val patch = kotlinx.serialization.json.Json.parseToJsonElement("""{"a":null,"b":{"c":9},"e":"x"}""")
        assertEquals("""{"b":{"c":9,"d":3},"e":"x"}""", base.merged(patch).toString())
        assertEquals(listOf("id", "region"), Placeholders.names("{{account.id}}/{{account.region}}/{{token}}", "account"))
        assertEquals("u-1/{{account.x}}", Placeholders.fill("{{account.id}}/{{account.x}}", mapOf("id" to "u-1"), "account"))
    }
}
