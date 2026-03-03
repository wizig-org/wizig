# `examples/app/WizigExample/.wizig/generated/kotlin/dev/wizig/WizigGeneratedApi.kt`

_Language: Kotlin_

## Public API

### `WizigGeneratedEventSink` (interface)

No declaration docs available.

```kotlin
interface WizigGeneratedEventSink {
```

### `WizigGeneratedFfiException` (class)

No declaration docs available.

```kotlin
class WizigGeneratedFfiException(
    val domain: String,
    val code: Int,
    val detail: String,
) : RuntimeException("$domain[$code]: $detail")

private object WizigGeneratedNativeBridge {
```

### `WizigGeneratedApi` (class)

No declaration docs available.

```kotlin
class WizigGeneratedApi(
    private var sink: WizigGeneratedEventSink? = null,
```

### `setEventSink` (fun)

No declaration docs available.

```kotlin
    fun setEventSink(next: WizigGeneratedEventSink?) {
```
