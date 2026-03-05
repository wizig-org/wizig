# `sdk/android/src/main/kotlin/dev/wizig/WizigRuntime.kt`

_Language: Kotlin_

## Public API

### `WizigFfiException` (class)

Exception returned by the legacy Android runtime shim.

Android integrations are JNI-first: use generated bindings in
`WizigGeneratedApi.kt` produced by `wizig codegen`.

```kotlin
class WizigFfiException(
    val function: String,
    val status: Int,
    message: String? = null,
```

### `WizigRuntime` (class)

Legacy runtime shim kept for source compatibility.

Wizig no longer performs direct JNA-based calls on Android. Runtime access
should go through JNI-backed generated bindings (`WizigGeneratedApi`).

```kotlin
class WizigRuntime(
    val plugins: List<PluginDescriptor> = GeneratedPluginRegistrant.plugins,
```

### `lastError` (var)

No declaration docs available.

```kotlin
    var lastError: WizigFfiException? = WizigFfiException(
```

### `isAvailable` (val)

No declaration docs available.

```kotlin
    val isAvailable: Boolean
```

### `hasPlugin` (fun)

No declaration docs available.

```kotlin
    fun hasPlugin(id: String): Boolean = plugins.any { it.id == id }
```

### `echo` (fun)

No declaration docs available.

```kotlin
    fun echo(input: String): String {
```

### `close` (fun)

No declaration docs available.

```kotlin
    override fun close() {
```
