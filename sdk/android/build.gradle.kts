plugins {
    alias(libs.plugins.kotlin.jvm)
    `java-library`
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("net.java.dev.jna:jna:5.14.0")
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}
