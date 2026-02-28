# `sdk/ios/Sources/Wizig/WizigRuntime.swift`

_Language: Swift_

## Public API

### `WizigRuntimeError` (enum)

No declaration docs available.

```swift
public enum WizigRuntimeError: Error, CustomStringConvertible {
```

### `description` (var)

No declaration docs available.

```swift
    public var description: String {
```

### `WizigRuntime` (class)

No declaration docs available.

```swift
public final class WizigRuntime {
```

### `plugins` (let)

No declaration docs available.

```swift
    public let plugins: [PluginDescriptor]
```

### `lastError` (var)

No declaration docs available.

```swift
    public private(set) var lastError: WizigRuntimeError?
```

### `isAvailable` (var)

No declaration docs available.

```swift
    public var isAvailable: Bool {
```

### `init` (init)

No declaration docs available.

```swift
    public init(
        appName: String = "wizig-ios",
        plugins: [PluginDescriptor] = GeneratedPluginRegistrant.plugins,
        libraryPath: String? = nil
    ) {
```

### `close` (func)

No declaration docs available.

```swift
    public func close() {
```

### `hasPlugin` (func)

No declaration docs available.

```swift
    public func hasPlugin(_ id: String) -> Bool {
```

### `echo` (func)

No declaration docs available.

```swift
    public func echo(_ input: String) throws -> String {
```
