package dev.wizig

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.LongByReference
import com.sun.jna.ptr.PointerByReference

class WizigFfiException(
    val function: String,
    val status: Int,
    message: String? = null,
) : RuntimeException(message ?: "$function failed with status $status")

private object WizigStatus {
    const val OK = 0
    const val INTERNAL_ERROR = 255
}

private interface WizigFfi : Library {
    fun wizig_runtime_new(appNamePtr: ByteArray, appNameLen: Long, outHandle: PointerByReference): Int
    fun wizig_runtime_free(handle: Pointer?)

    fun wizig_runtime_echo(
        handle: Pointer?,
        inputPtr: ByteArray,
        inputLen: Long,
        outPtr: PointerByReference,
        outLen: LongByReference,
    ): Int

    fun wizig_bytes_free(ptr: Pointer?, len: Long)
}

class WizigRuntime(
    val plugins: List<PluginDescriptor> = GeneratedPluginRegistrant.plugins,
    appName: String = "wizig-android",
    libraryName: String = System.getenv("WIZIG_FFI_LIB") ?: "wizigffi",
) : AutoCloseable {
    private var ffi: WizigFfi? = null
    private var handle: Pointer? = null

    var lastError: WizigFfiException? = null
        private set

    val isAvailable: Boolean
        get() = ffi != null && handle != null && lastError == null

    init {
        initialize(appName, libraryName)
    }

    fun hasPlugin(id: String): Boolean = plugins.any { it.id == id }

    fun echo(input: String): String {
        val ffi = ffi ?: throw (lastError ?: WizigFfiException("wizig_runtime_echo", WizigStatus.INTERNAL_ERROR))
        val handle = handle ?: throw (lastError ?: WizigFfiException("wizig_runtime_echo", WizigStatus.INTERNAL_ERROR))

        val inputBytes = input.toByteArray(Charsets.UTF_8)
        val outPtr = PointerByReference()
        val outLen = LongByReference()

        val status = ffi.wizig_runtime_echo(
            handle,
            inputBytes,
            inputBytes.size.toLong(),
            outPtr,
            outLen,
        )
        ensureStatus("wizig_runtime_echo", status)

        val bytesPtr = outPtr.value ?: throw WizigFfiException(
            function = "wizig_runtime_echo",
            status = WizigStatus.INTERNAL_ERROR,
            message = "wizig_runtime_echo returned null buffer",
        )
        val bytesLen = outLen.value

        return try {
            val data = bytesPtr.getByteArray(0, bytesLen.toInt())
            data.toString(Charsets.UTF_8)
        } finally {
            ffi.wizig_bytes_free(bytesPtr, bytesLen)
        }
    }

    override fun close() {
        val ffi = ffi
        val handle = handle
        if (ffi != null && handle != null) {
            ffi.wizig_runtime_free(handle)
        }
        this.handle = null
    }

    private fun initialize(appName: String, libraryName: String) {
        val appBytes = appName.toByteArray(Charsets.UTF_8)
        val outHandle = PointerByReference()

        runCatching {
            val loadedFfi = Native.load(libraryName, WizigFfi::class.java)
            val status = loadedFfi.wizig_runtime_new(appBytes, appBytes.size.toLong(), outHandle)
            ensureStatus("wizig_runtime_new", status)

            val runtimeHandle = outHandle.value ?: throw WizigFfiException(
                function = "wizig_runtime_new",
                status = WizigStatus.INTERNAL_ERROR,
                message = "wizig_runtime_new returned null handle",
            )

            ffi = loadedFfi
            handle = runtimeHandle
        }.onFailure { throwable ->
            lastError = when (throwable) {
                is WizigFfiException -> throwable
                else -> WizigFfiException(
                    function = "wizig_runtime_new",
                    status = WizigStatus.INTERNAL_ERROR,
                    message = throwable.message,
                )
            }
        }
    }

    private fun ensureStatus(function: String, status: Int) {
        if (status == WizigStatus.OK) return
        throw WizigFfiException(function = function, status = status)
    }
}
