package dev.ziggy.example

import dev.ziggy.ZiggyRuntime

class App {
    val greeting: String
        get() {
            ZiggyRuntime(appName = "ziggy-example-android").use { runtime ->
                val echo = runCatching { runtime.echo("hello") }.getOrElse { "unavailable" }
                return "Hello Ziggy! Registered plugins: ${runtime.plugins.size}; runtimeAvailable=${runtime.isAvailable}; echo=$echo"
            }
        }
}

fun main() {
    println(App().greeting)
}
