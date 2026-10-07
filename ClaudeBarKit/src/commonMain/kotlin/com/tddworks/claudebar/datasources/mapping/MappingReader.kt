package com.tddworks.claudebar.datasources.mapping

import com.tddworks.claudebar.datasources.Reading

/**
 * The worker that reads what this mapping says — the one place a case of `Mapping` meets its
 * mapper. [scripts] gives a mapping script's text by the file name a definition gives;
 * [nowSeconds] is the fetch's clock (Unix seconds).
 */
internal fun Mapping.reader(
    scripts: (String) -> String?,
    engine: ScriptEngine,
    nowSeconds: () -> Double,
    zones: TimeZones = systemTimeZones(),
): Reading = when (this) {
    is Mapping.Json -> JSONMapper(mapping, nowSeconds)
    is Mapping.Text -> TextMapper(mapping, nowSeconds)
    is Mapping.Script -> ScriptMapper(mapping.file, scripts(mapping.file), mapping.values, engine, nowSeconds, zones)
    Mapping.Usage -> UsageMapper(nowSeconds)
}
