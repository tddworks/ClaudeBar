package com.tddworks.claudebar.providers

import platform.AppKit.NSPasteboard
import platform.AppKit.NSPasteboardTypeString

/** The Mac's pasteboard — the general one, where a CLI's "copied to clipboard" lands. */
internal class SystemClipboard(
    private val pasteboard: NSPasteboard = NSPasteboard.generalPasteboard,
) : Clipboard {
    override fun text(): String? = pasteboard.stringForType(NSPasteboardTypeString)
}
