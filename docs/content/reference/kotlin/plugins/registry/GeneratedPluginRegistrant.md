# `plugins/registry/GeneratedPluginRegistrant.kt`

_Language: Kotlin_

## Public API

### `PluginDescriptor` (class)

No declaration docs available.

```kotlin
data class PluginDescriptor(
    val id: String,
    val version: String,
    val apiVersion: UInt,
    val manifestPath: String,
    val capabilities: List<String>,
    val iosSpm: List<String>,
    val androidMaven: List<String>
)

object GeneratedPluginRegistrant {
```

### `GeneratedPluginRegistrant` (object)

No declaration docs available.

```kotlin
object GeneratedPluginRegistrant {
```

### `plugins` (val)

No declaration docs available.

```kotlin
    val plugins: List<PluginDescriptor> = listOf(
```
