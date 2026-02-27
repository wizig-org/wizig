package dev.ziggy

import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.LongByReference
import com.sun.jna.ptr.PointerByReference

class ZiggyFfiException(
    val function: String,
    val status: Int,
    message: String? = null,
) : RuntimeException(message ?: "$function failed with status $status")

private object ZiggyStatus {
    const val OK = 0
    const val INTERNAL_ERROR = 255
}

private interface ZiggyFfi : Library {
    fun ziggy_runtime_new(appNamePtr: ByteArray, appNameLen: Long, outHandle: PointerByReference): Int
    fun ziggy_runtime_free(handle: Pointer?)

    fun ziggy_runtime_echo(
        handle: Pointer?,
        inputPtr: ByteArray,
        inputLen: Long,
        outPtr: PointerByReference,
        outLen: LongByReference,
    ): Int

    fun ziggy_bytes_free(ptr: Pointer?, len: Long)
}

class ZiggyRuntime(
    val plugins: List<PluginDescriptor> = GeneratedPluginRegistrant.plugins,
    appName: String = "ziggy-android",
    libraryName: String = System.getenv("ZIGGY_FFI_LIB") ?: "ziggyffi",
) : AutoCloseable {
    private var ffi: ZiggyFfi? = null
    private var handle: Pointer? = null

    var lastError: ZiggyFfiException? = null
        private set

    val isAvailable: Boolean
        get() = ffi != null && handle != null && lastError == null

    init {
        initialize(appName, libraryName)
    }

    fun hasPlugin(id: String): Boolean = plugins.any { it.id == id }

    fun echo(input: String): String {
        val ffi = ffi ?: throw (lastError ?: ZiggyFfiException("ziggy_runtime_echo", ZiggyStatus.INTERNAL_ERROR))
        val handle = handle ?: throw (lastError ?: ZiggyFfiException("ziggy_runtime_echo", ZiggyStatus.INTERNAL_ERROR))

        val inputBytes = input.toByteArray(Charsets.UTF_8)
        val outPtr = PointerByReference()
        val outLen = LongByReference()

        val status = ffi.ziggy_runtime_echo(
            handle,
            inputBytes,
            inputBytes.size.toLong(),
            outPtr,
            outLen,
        )
        ensureStatus("ziggy_runtime_echo", status)

        val bytesPtr = outPtr.value ?: throw ZiggyFfiException(
            function = "ziggy_runtime_echo",
            status = ZiggyStatus.INTERNAL_ERROR,
            message = "ziggy_runtime_echo returned null buffer",
        )
        val bytesLen = outLen.value

        return try {
            val data = bytesPtr.getByteArray(0, bytesLen.toInt())
            data.toString(Charsets.UTF_8)
        } finally {
            ffi.ziggy_bytes_free(bytesPtr, bytesLen)
        }
    }

    override fun close() {
        val ffi = ffi
        val handle = handle
        if (ffi != null && handle != null) {
            ffi.ziggy_runtime_free(handle)
        }
        this.handle = null
    }

    private fun initialize(appName: String, libraryName: String) {
        val appBytes = appName.toByteArray(Charsets.UTF_8)
        val outHandle = PointerByReference()

        runCatching {
            val loadedFfi = Native.load(libraryName, ZiggyFfi::class.java)
            val status = loadedFfi.ziggy_runtime_new(appBytes, appBytes.size.toLong(), outHandle)
            ensureStatus("ziggy_runtime_new", status)

            val runtimeHandle = outHandle.value ?: throw ZiggyFfiException(
                function = "ziggy_runtime_new",
                status = ZiggyStatus.INTERNAL_ERROR,
                message = "ziggy_runtime_new returned null handle",
            )

            ffi = loadedFfi
            handle = runtimeHandle
        }.onFailure { throwable ->
            lastError = when (throwable) {
                is ZiggyFfiException -> throwable
                else -> ZiggyFfiException(
                    function = "ziggy_runtime_new",
                    status = ZiggyStatus.INTERNAL_ERROR,
                    message = throwable.message,
                )
            }
        }
    }

    private fun ensureStatus(function: String, status: Int) {
        if (status == ZiggyStatus.OK) return
        throw ZiggyFfiException(function = function, status = status)
    }
}
