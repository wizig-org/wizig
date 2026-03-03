package dev.wizig

/**
 * Exception returned by the legacy Android runtime shim.
 *
 * Android integrations are JNI-first: use generated bindings in
 * `WizigGeneratedApi.kt` produced by `wizig codegen`.
 */
class WizigFfiException(
    val function: String,
    val status: Int,
    message: String? = null,
) : RuntimeException(message ?: "$function failed with status $status")

/**
 * Legacy runtime shim kept for source compatibility.
 *
 * Wizig no longer performs direct JNA-based calls on Android. Runtime access
 * should go through JNI-backed generated bindings (`WizigGeneratedApi`).
 */
class WizigRuntime(
    val plugins: List<PluginDescriptor> = GeneratedPluginRegistrant.plugins,
    appName: String = "wizig-android",
) : AutoCloseable {
    var lastError: WizigFfiException? = WizigFfiException(
        function = "wizig_runtime_new",
        status = 255,
        message = "Android direct runtime access is disabled. Use JNI-backed WizigGeneratedApi instead (appName=$appName).",
    )
        private set

    val isAvailable: Boolean
        get() = false

    fun hasPlugin(id: String): Boolean = plugins.any { it.id == id }

    fun echo(input: String): String {
        throw (lastError ?: WizigFfiException("wizig_runtime_echo", 255, "runtime unavailable for input '$input'"))
    }

    override fun close() {
        // No-op: JNI lifecycle is managed by generated bindings.
    }
}
