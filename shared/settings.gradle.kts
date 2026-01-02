pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "claudebar-shared"

enableFeaturePreview("TYPESAFE_PROJECT_ACCESSORS")

include(":domain")
include(":infrastructure")
