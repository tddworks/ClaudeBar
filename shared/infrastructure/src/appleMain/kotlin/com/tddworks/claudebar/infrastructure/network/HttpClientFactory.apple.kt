package com.tddworks.claudebar.infrastructure.network

import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import kotlinx.serialization.json.Json
import platform.Foundation.NSURLAuthenticationChallenge
import platform.Foundation.NSURLAuthenticationMethodServerTrust
import platform.Foundation.NSURLCredential
import platform.Foundation.NSURLSessionAuthChallengeDisposition
import platform.Foundation.NSURLSessionAuthChallengePerformDefaultHandling
import platform.Foundation.NSURLSessionAuthChallengeUseCredential
import platform.Foundation.serverTrust

/**
 * Apple platforms implementation using Darwin engine.
 * Works on macOS, iOS, tvOS, watchOS.
 *
 * Supports self-signed certificates for localhost connections (Antigravity).
 */
actual fun createHttpClient(
    json: Json,
    enableLogging: Boolean
): HttpClient {
    return HttpClient(Darwin) {
        engine {
            configureRequest {
                setAllowsCellularAccess(true)
            }
            // Handle self-signed certificates for localhost
            handleChallenge { _, challenge ->
                handleTlsChallenge(challenge)
            }
        }
    }.configureCommon(json, enableLogging)
}

/**
 * Handles TLS challenges, accepting self-signed certificates for localhost only.
 */
private fun handleTlsChallenge(
    challenge: NSURLAuthenticationChallenge
): Pair<NSURLSessionAuthChallengeDisposition, NSURLCredential?> {
    val host = challenge.protectionSpace.host
    val authMethod = challenge.protectionSpace.authenticationMethod

    // Only handle server trust challenges for localhost
    if (authMethod == NSURLAuthenticationMethodServerTrust &&
        (host == "127.0.0.1" || host == "localhost")
    ) {
        val serverTrust = challenge.protectionSpace.serverTrust
        if (serverTrust != null) {
            val credential = NSURLCredential.credentialForTrust(serverTrust)
            return Pair(NSURLSessionAuthChallengeUseCredential, credential)
        }
    }

    // Default handling for all other challenges
    return Pair(NSURLSessionAuthChallengePerformDefaultHandling, null)
}
