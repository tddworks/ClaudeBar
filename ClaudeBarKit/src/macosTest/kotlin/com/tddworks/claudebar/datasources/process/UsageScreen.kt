package com.tddworks.claudebar.datasources.process

/** The ready markers of a `/usage` screen, as the shipping definition and the Swift rule had them. */
internal val usageScreenRule = CLICompletionRule(
    listOf(
        CLICompletionRule.Marker.row("Current session"),
        CLICompletionRule.Marker("% used"),
        CLICompletionRule.Marker("% left"),
        CLICompletionRule.Marker("rate limited"),
        CLICompletionRule.Marker("Error:"),
        CLICompletionRule.Marker("/usage is only available"),
    ),
)
