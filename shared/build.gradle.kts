plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.touchlab.skie) apply false
}

allprojects {
    group = "com.tddworks.claudebar"
    version = "1.0.0-SNAPSHOT"
}
