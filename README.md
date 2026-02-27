# Ziggy

Ziggy is a mobile-first framework architecture with Zig core logic and native host UIs.

## Core Commands

```sh
zig build
zig build test
```

## Plugin Registry

```sh
zig build run -- plugin validate examples/plugin-hello/ziggy-plugin.toml
zig build run -- plugin sync examples
```

## App Scaffolding

```sh
zig build run -- create ios MyApp examples/ios/MyApp
zig build run -- create android MyApp examples/android/MyApp
```

## Run Apps

```sh
# iOS (interactive simulator selection + lldb attach)
zig build run -- run ios examples/ios/ZiggyExample

# Android (interactive device selection + jdb attach or logcat fallback)
zig build run -- run android examples/android/ZiggyExample
```

## FFI Runtime Notes

- Build host FFI artifacts with `zig build`.
- Shared library output is installed under `zig-out/lib` (for example `zig-out/lib/libziggyffi.dylib` on macOS).
- Swift/Kotlin runtimes read `ZIGGY_FFI_LIB` to locate the library if needed.
