package com.tddworks.claudebar.providers

/** How much work a refresh should do, and whether it counts as the person asking. */
public enum class RefreshKind {
    /** A genuine click: the most expensive work is allowed, and success means "the user connected". */
    INTERACTIVE,

    /** The periodic menu-bar poll: stays cheap, skipping work nobody glances at (#204). */
    BACKGROUND,

    /** Started by the app without a click — the popover opening. Providers choose what it means (#216). */
    PASSIVE,
}
