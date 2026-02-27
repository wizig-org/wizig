plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "ZiggyExample"
include("app")
include(":ziggy-sdk")
project(":ziggy-sdk").projectDir = file("../../../sdk/android")
