package com.tddworks.claudebar.monitoring

import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.toKString
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.flow.onCompletion
import platform.AppKit.NSWorkspace
import platform.AppKit.NSWorkspaceDidWakeNotification
import platform.AppKit.NSWorkspaceScreensDidSleepNotification
import platform.AppKit.NSWorkspaceScreensDidWakeNotification
import platform.AppKit.NSWorkspaceWillSleepNotification
import platform.CoreFoundation.CFRelease
import platform.CoreFoundation.CFStringGetCString
import platform.CoreFoundation.kCFStringEncodingUTF8
import platform.Foundation.NSNotificationCenter
import platform.IOKit.IOPSCopyPowerSourcesInfo
import platform.IOKit.IOPSGetProvidingPowerSourceType
import platform.darwin.NSObjectProtocol

/**
 * The Mac's power state, from AppKit's workspace sleep/wake notifications and IOKit's power
 * sources (#204). The display sleeping while the Mac keeps running (`screensDidSleep`) is the
 * moment the old loop kept starting CLIs and warming the CPU. Battery is read on demand — no
 * AC/battery notification exists, and the read is cheap — so the loop reads it once per tick.
 */
internal class SystemPowerStateProvider(
    /** NSWorkspace's own notification center — the only one that posts its sleep and wake. */
    private val center: NSNotificationCenter = NSWorkspace.sharedWorkspace.notificationCenter,
) : PowerStateProvider {
    private val lock = SynchronizedObject()
    private var asleep = false
    private val listeners = mutableListOf<Channel<PowerEvent>>()
    private val observers: List<NSObjectProtocol>

    init {
        val sleeps = listOf(NSWorkspaceWillSleepNotification, NSWorkspaceScreensDidSleepNotification)
            .map { name -> center.addObserverForName(name, null, null) { _ -> handle(PowerEvent.WILL_SLEEP) } }
        val wakes = listOf(NSWorkspaceDidWakeNotification, NSWorkspaceScreensDidWakeNotification)
            .map { name -> center.addObserverForName(name, null, null) { _ -> handle(PowerEvent.DID_WAKE) } }
        observers = sleeps + wakes
    }

    override val isDisplayAsleep: Boolean get() = synchronized(lock) { asleep }

    @OptIn(ExperimentalForeignApi::class)
    override val isOnBattery: Boolean
        get() {
            val info = IOPSCopyPowerSourcesInfo() ?: return false
            try {
                val type = IOPSGetProvidingPowerSourceType(info) ?: return false
                return memScoped {
                    val text = allocArray<ByteVar>(64)
                    CFStringGetCString(type, text, 64, kCFStringEncodingUTF8) && text.toKString() == BATTERY_POWER
                }
            } finally {
                CFRelease(info)
            }
        }

    /** Listened to from the moment it is asked for, so a transition before collection still arrives. */
    override fun events(): Flow<PowerEvent> {
        val channel = Channel<PowerEvent>(Channel.UNLIMITED)
        synchronized(lock) { listeners += channel }
        return channel.consumeAsFlow().onCompletion { synchronized(lock) { listeners -= channel } }
    }

    /** Stops listening and ends every flow it handed out. */
    fun close() {
        observers.forEach(center::removeObserver)
        val pending = synchronized(lock) { listeners.toList().also { listeners.clear() } }
        pending.forEach { it.close() }
    }

    /** The asleep flag first, then the event — so a listener re-reading [isDisplayAsleep] sees the new state. */
    private fun handle(event: PowerEvent) {
        val current = synchronized(lock) {
            asleep = event == PowerEvent.WILL_SLEEP
            listeners.toList()
        }
        current.forEach { it.trySend(event) }
    }

    private companion object {
        /** `kIOPSBatteryPowerValue`, a C string macro. */
        const val BATTERY_POWER = "Battery Power"
    }
}
