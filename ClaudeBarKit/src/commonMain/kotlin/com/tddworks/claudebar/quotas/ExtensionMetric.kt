package com.tddworks.claudebar.quotas

import kotlin.native.ObjCName

/**
 * A metric an extension section shows, for data that fits no quota, cost or day.
 * Interim (CANONICAL_MODEL): leaves the kernel for a mapping in DataSources.
 */
data class ExtensionMetric(
    val label: String,
    val value: String,
    val unit: String,
    val icon: String?,
    val color: String?,
    val delta: MetricDelta?,
    @ObjCName("progressOrNull") val progress: Double?,
    /** Section when an aggregating provider made it (an account row); null in the flat grid. */
    val group: String?,
)

/** A comparison for a metric ("Vs Mar 16 -$701.58 (98.6%)"). */
data class MetricDelta(val vs: String, val value: String, @ObjCName("percentOrNull") val percent: Double?)
