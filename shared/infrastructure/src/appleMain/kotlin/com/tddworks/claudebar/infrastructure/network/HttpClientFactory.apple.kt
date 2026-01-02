package com.tddworks.claudebar.infrastructure.network

import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.serialization.json.Json
import platform.Foundation.NSURLAuthenticationMethodServerTrust
import platform.Foundation.NSURLCredential
import platform.Foundation.NSURLSessionAuthChallengePerformDefaultHandling
import platform.Foundation.NSURLSessionAuthChallengeUseCredential
import platform.Foundation.credentialForTrust
import platform.Foundation.serverTrust

/**
 * Apple platforms implementation using Darwin engine.
 * Works on macOS, iOS, tvOS, watchOS.
 *
 * Supports self-signed certificates for localhost connections (Antigravity).
 */
@OptIn(ExperimentalForeignApi::class)
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
            handleChallenge { session, task, challenge, completionHandler ->
                val host = challenge.protectionSpace.host
                val authMethod = challenge.protectionSpace.authenticationMethod

                // Accept self-signed certs for localhost only
                if (authMethod == NSURLAuthenticationMethodServerTrust &&
                    (host == "127.0.0.1" || host == "localhost")
                ) {
                    val serverTrust = challenge.protectionSpace.serverTrust
                    if (serverTrust != null) {
                        val credential = NSURLCredential.credentialForTrust(serverTrust)
                        completionHandler(NSURLSessionAuthChallengeUseCredential, credential)
                        return@handleChallenge
                    }
                }

                // Default handling for all other challenges
                completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, null)
            }
        }
    }.configureCommon(json, enableLogging)
}
