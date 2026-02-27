# Plugin Registry

This folder is reserved for generated registrants and lockfiles.

Generate artifacts with:

```sh
zig build run -- plugin sync examples
```

Generated artifacts:

- `generated_plugins.zig`
- `plugins.lock.toml`

Platform registrants are generated into SDK source paths:

- `sdk/ios/Sources/Ziggy/GeneratedPluginRegistrant.swift`
- `sdk/android/src/main/kotlin/dev/ziggy/GeneratedPluginRegistrant.kt`
