package com.tddworks.claudebar.alerting

import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import platform.Foundation.NSURLRequestReloadIgnoringLocalAndRemoteCacheData

/**
 * The HTTP client [NotifyGatewayClient] runs on, on macOS. Every gateway URL carries the
 * device token, and URLSession's shared cache is a plaintext file in ~/Library/Caches, so this
 * session has no cache at all.
 */
internal fun notifyGatewayHttpClient(): HttpClient = HttpClient(Darwin) {
    engine {
        configureSession {
            setURLCache(null)
            setRequestCachePolicy(NSURLRequestReloadIgnoringLocalAndRemoteCacheData)
        }
    }
}
