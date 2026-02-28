# Plugin Registry

This folder is reserved for generated registrants and lockfiles.

Generate artifacts with:

```sh
zig build run -- plugin sync .
```

Generated artifacts:

- `generated_plugins.zig`
- `plugins.lock.toml`

Platform registrants are generated into app-local generated paths:

- `.ziggy/generated/swift/GeneratedPluginRegistrant.swift`
- `.ziggy/generated/kotlin/dev/ziggy/GeneratedPluginRegistrant.kt`
