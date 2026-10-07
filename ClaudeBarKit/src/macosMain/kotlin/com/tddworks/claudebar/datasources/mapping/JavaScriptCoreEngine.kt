package com.tddworks.claudebar.datasources.mapping

import platform.Foundation.NSNull
import platform.Foundation.NSString
import platform.JavaScriptCore.JSContext
import platform.JavaScriptCore.setObject

/** [ScriptEngine] on JavaScriptCore: a fresh context per run, with nothing but what the run hands it. */
internal class JavaScriptCoreEngine : ScriptEngine {
    override fun run(
        sources: List<String>,
        strings: Map<String, String>,
        functions: Map<String, (String) -> Double?>,
        expression: String,
    ): ScriptRun {
        val context = JSContext()
        var exception: String? = null
        context.exceptionHandler = { _, value -> exception = value?.toString() }

        for ((name, function) in functions) {
            val block: (String?) -> Any? = { text -> function(text.orEmpty()) ?: NSNull() }
            context.setObject(block, forKeyedSubscript = key(name))
        }
        for ((name, value) in strings) context.setObject(value, forKeyedSubscript = key(name))

        for (source in sources) context.evaluateScript(source)
        exception?.let { return ScriptRun.LoadFailed(it) }

        val output = context.evaluateScript(expression)
        exception?.let { return ScriptRun.Threw(it) }
        if (output == null || output.isUndefined()) return ScriptRun.Value(null)
        return ScriptRun.Value(output.toString())
    }

    @Suppress("CAST_NEVER_SUCCEEDS")
    private fun key(name: String) = name as NSString
}
