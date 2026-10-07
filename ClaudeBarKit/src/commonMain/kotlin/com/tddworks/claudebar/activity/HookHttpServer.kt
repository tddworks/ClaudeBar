package com.tddworks.claudebar.activity

import com.tddworks.claudebar.diagnostics.AppLog
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.ApplicationCallPipeline
import io.ktor.server.cio.CIO
import io.ktor.server.cio.CIOApplicationEngine
import io.ktor.server.engine.EmbeddedServer
import io.ktor.server.engine.embeddedServer
import io.ktor.server.request.receiveChannel
import io.ktor.server.response.respond
import io.ktor.utils.io.readRemaining
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.io.readString
import kotlin.time.Clock

/**
 * Receives Claude Code's hook events: `POST /hook` on 127.0.0.1 only, every request answered
 * `200` with no body. Listens on [defaultPort] (0 picks a free one) and leaves the port it got
 * in [portDiscovery]'s file for the installed hook to read.
 */
internal class HookHttpServer(
    private val portDiscovery: PortDiscovery,
    private val defaultPort: Int = HookConstants.DEFAULT_PORT,
    private val nowSeconds: () -> Double = { Clock.System.now().toEpochMilliseconds() / 1000.0 },
) : HookEventReceiver {
    private val lock = SynchronizedObject()
    private var server: EmbeddedServer<CIOApplicationEngine, CIOApplicationEngine.Configuration>? = null
    private var events: Channel<SessionEvent>? = null
    private var port = 0

    /** The port listened on; 0 until started. */
    val actualPort: Int get() = synchronized(lock) { port }

    /** A failure to listen is logged and ends the flow at once, as a stopped receiver does. */
    override suspend fun start(): Flow<SessionEvent> {
        val channel = Channel<SessionEvent>(Channel.UNLIMITED)
        val flow = channel.consumeAsFlow().onCompletion { stop() }
        val started = embeddedServer(CIO, port = defaultPort, host = LOOPBACK) {
            intercept(ApplicationCallPipeline.Call) { handle(context, channel) }
        }
        try {
            started.startSuspend(wait = false)
        } catch (error: Throwable) {
            AppLog.hooks.error("Hook HTTP server failed: ${error.message}")
            channel.close()
            return flow
        }
        val listening = started.engine.resolvedConnectors().first().port
        synchronized(lock) {
            server = started
            events = channel
            port = listening
        }
        runCatching { portDiscovery.writePort(listening) }
        AppLog.hooks.info("Hook HTTP server listening on port $listening")
        return flow
    }

    override suspend fun stop() {
        val (running, channel) = synchronized(lock) {
            (server to events).also {
                server = null
                events = null
            }
        }
        if (running == null && channel == null) return
        running?.stopSuspend(gracePeriodMillis = 0, timeoutMillis = 500)
        channel?.close()
        portDiscovery.removePortFile()
        AppLog.hooks.info("Hook HTTP server stopped")
    }

    private suspend fun handle(call: ApplicationCall, channel: Channel<SessionEvent>) {
        try {
            if (call.request.local.method != HttpMethod.Post || !call.request.local.uri.startsWith("/hook")) {
                AppLog.hooks.debug("Rejected non-POST /hook request")
                return
            }
            // Hook payloads are small; 64 KB is the most read, as it always was.
            val body = call.receiveChannel().readRemaining(MAX_BODY_BYTES).readString()
            val processId = call.request.headers[HookConstants.PROCESS_ID_HEADER]
            val event = SessionEventParser.parse(body, nowSeconds(), processId)
            if (event != null) {
                AppLog.hooks.info("Received hook event: ${event.eventName.rawValue} for session ${event.sessionId}")
                channel.trySend(event)
            } else {
                AppLog.hooks.warning("Failed to parse hook event payload")
            }
        } catch (error: Exception) {
            AppLog.hooks.debug("Connection error: ${error.message}")
        } finally {
            call.respond(HttpStatusCode.OK)
        }
    }

    private companion object {
        const val LOOPBACK = "127.0.0.1"
        const val MAX_BODY_BYTES = 65_536L
    }
}
