package com.tddworks.claudebar.datasources.fetch

import com.tddworks.claudebar.datasources.NetworkClient
import io.ktor.client.engine.darwin.Darwin
import platform.Foundation.NSCalendar
import platform.Foundation.NSDate
import platform.Foundation.NSURLAuthenticationMethodServerTrust
import platform.Foundation.NSURLCredential
import platform.Foundation.NSURLSessionAuthChallengePerformDefaultHandling
import platform.Foundation.NSURLSessionAuthChallengeUseCredential
import platform.Foundation.credentialForTrust
import platform.Foundation.dateWithTimeIntervalSince1970
import platform.Foundation.serverTrust
import platform.Foundation.timeIntervalSince1970

private val shared: NetworkClient by lazy { KtorNetworkClient.over(Darwin.create()) }

internal actual fun systemNetworkClient(): NetworkClient = shared

internal actual fun insecureLocalhostNetworkClient(timeoutSeconds: Double): NetworkClient = LoopbackNetworkClient(
    KtorNetworkClient.over(
        Darwin.create {
            // Any certificate, but only from this Mac: everyone else gets the system's checks.
            handleChallenge { _, _, challenge, completionHandler ->
                val space = challenge.protectionSpace
                val trust = space.serverTrust
                if (space.host.lowercase() in setOf("127.0.0.1", "localhost") &&
                    space.authenticationMethod == NSURLAuthenticationMethodServerTrust && trust != null
                ) {
                    completionHandler(NSURLSessionAuthChallengeUseCredential, NSURLCredential.credentialForTrust(trust))
                } else {
                    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, null)
                }
            }
        },
        followRedirects = false,
    ),
    timeoutSeconds,
)

internal actual fun startOfLocalDaySeconds(seconds: Double): Double =
    NSCalendar.currentCalendar.startOfDayForDate(NSDate.dateWithTimeIntervalSince1970(seconds)).timeIntervalSince1970
