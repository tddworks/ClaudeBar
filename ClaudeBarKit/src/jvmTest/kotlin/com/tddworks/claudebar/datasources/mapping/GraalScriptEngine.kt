package com.tddworks.claudebar.datasources.mapping

import org.graalvm.polyglot.Context
import org.graalvm.polyglot.PolyglotException
import org.graalvm.polyglot.proxy.ProxyExecutable

/**
 * [ScriptEngine] on GraalJS, for JUnit: a fresh context per run with nothing but what the run
 * hands it — no file, network, process or host access — as the JavaScriptCore engine does on the Mac.
 */
internal class GraalScriptEngine : ScriptEngine {
    override fun run(
        sources: List<String>,
        strings: Map<String, String>,
        functions: Map<String, (String) -> Double?>,
        expression: String,
    ): ScriptRun {
        val context = runCatching {
            Context.newBuilder("js").allowAllAccess(false).option("engine.WarnInterpreterOnly", "false").build()
        }.getOrElse { return ScriptRun.Unavailable }
        return context.use {
            val bindings = it.getBindings("js")
            for ((name, function) in functions) {
                bindings.putMember(name, ProxyExecutable { args -> function(args.firstOrNull()?.takeUnless { a -> a.isNull }?.asString().orEmpty()) })
            }
            for ((name, value) in strings) bindings.putMember(name, value)
            try {
                for (source in sources) it.eval("js", source)
            } catch (error: PolyglotException) {
                return ScriptRun.LoadFailed(error.message.orEmpty())
            }
            try {
                val output = it.eval("js", expression)
                if (output == null || output.isNull && output.toString() == "undefined") ScriptRun.Value(null)
                else ScriptRun.Value(output.toString())
            } catch (error: PolyglotException) {
                ScriptRun.Threw(error.message.orEmpty())
            }
        }
    }
}
