package com.tddworks.claudebar.datasources.fetch.aws

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.time.Instant

/**
 * SigV4 against AWS's published test suite (`resources/aws-sigv4`, from aws-c-auth's copy of
 * the `aws-sig-v4-test-suite`): each case's canonical request, string to sign and signature.
 */
class SignatureV4Test {
    private class Case(val request: SigningRequest, val credentials: AWSCredentials, val region: String, val service: String,
                       val nowSeconds: Double, val signBody: Boolean, val folder: File)

    private fun case(name: String): Case {
        val folder = File(javaClass.getResource("/aws-sigv4/$name")!!.toURI())
        val context = Json.parseToJsonElement(File(folder, "context.json").readText()).jsonObject
        val keys = context["credentials"]!!.jsonObject
        val text = File(folder, "request.txt").readText()
        val lines = text.substringBefore("\n\n").lines()
        val target = lines[0].substringAfter(' ').substringBeforeLast(" HTTP/1.1")
        val headers = lines.drop(1).filter { it.isNotBlank() }.map { it.substringBefore(':') to it.substringAfter(':') }
        val query = target.substringAfter('?', "").split('&').filter { it.isNotEmpty() }
            .map { it.substringBefore('=') to it.substringAfter('=', "") }
        return Case(
            SigningRequest(
                method = lines[0].substringBefore(' '),
                host = headers.first { it.first.equals("Host", true) }.second,
                path = target.substringBefore('?'),
                query = query,
                headers = headers.filterNot { it.first.equals("Host", true) },
                body = text.substringAfter("\n\n", "").encodeToByteArray(),
            ),
            AWSCredentials(
                keys["access_key_id"]!!.jsonPrimitive.content,
                keys["secret_access_key"]!!.jsonPrimitive.content,
                keys["token"]?.jsonPrimitive?.content,
            ),
            context["region"]!!.jsonPrimitive.content,
            context["service"]!!.jsonPrimitive.content,
            Instant.parse(context["timestamp"]!!.jsonPrimitive.content).epochSecond.toDouble(),
            context["sign_body"]!!.jsonPrimitive.boolean,
            folder,
        )
    }

    @ParameterizedTest
    @ValueSource(
        strings = [
            "get-vanilla", "get-vanilla-query-order-key-case", "get-vanilla-query-unreserved", "get-vanilla-empty-query-key",
            "get-header-value-trim", "get-header-key-duplicate", "get-unreserved", "get-utf8", "get-space-normalized",
            "get-slash-dot-slash-normalized", "get-vanilla-with-session-token", "post-vanilla", "post-vanilla-query",
            "post-header-key-case", "post-header-value-case", "post-x-www-form-urlencoded",
        ],
    )
    fun `should sign a request exactly as AWS's test suite says`(name: String) {
        val case = case(name)

        val signed = SignatureV4.sign(case.request, case.credentials, case.region, case.service, case.nowSeconds, case.signBody)

        assertEquals(File(case.folder, "header-canonical-request.txt").readText(), signed.canonicalRequest)
        assertEquals(File(case.folder, "header-string-to-sign.txt").readText(), signed.stringToSign)
        assertEquals(File(case.folder, "header-signature.txt").readText().trim(), signed.signature)
    }

    @Test
    fun `should send the date, the session token and the signature in the headers`() {
        val case = case("get-vanilla-with-session-token")

        val headers = SignatureV4.sign(case.request, case.credentials, case.region, case.service, case.nowSeconds).headers.toMap()

        assertEquals("20150830T123600Z", headers["X-Amz-Date"])
        assertEquals(case.credentials.sessionToken, headers["X-Amz-Security-Token"])
        assertEquals(
            "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, " +
                "SignedHeaders=host;x-amz-date;x-amz-security-token, " +
                "Signature=07ec1639c89043aa0e3e2de82b96708f198cceab042d4a97044c66dd9f74e7f8",
            headers["Authorization"],
        )
    }

    @Test
    fun `should never show the secret when credentials are printed`() {
        val printed = AWSCredentials("AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "token").toString()
        assertTrue("EXAMPLEKEY" !in printed && "token" !in printed && "AKIDEXAMPLE" !in printed, printed)
    }
}
