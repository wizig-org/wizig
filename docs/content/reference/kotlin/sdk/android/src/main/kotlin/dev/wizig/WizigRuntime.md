# `sdk/android/src/main/kotlin/dev/wizig/WizigRuntime.kt`

_Language: Kotlin_

## Public API

### `WizigFfiException` (class)

No declaration docs available.

```kotlin
class WizigFfiException(
    val function: String,
    val status: Int,
    message: String? = null,
```

### `WizigRuntime` (class)

No declaration docs available.

```kotlin
class WizigRuntime(
    val plugins: List<PluginDescriptor> = GeneratedPluginRegistrant.plugins,
```

### `lastError` (var)

No declaration docs available.

```kotlin
    var lastError: WizigFfiException? = null
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
