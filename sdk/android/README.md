# Ziggy Android SDK (Stub)

This module will wrap JNI bindings to Ziggy FFI shared libraries and expose Kotlin APIs.

Planned components:

- `ZiggyRuntime` Kotlin class
- generated plugin registrant integration
- Maven-native plugin adapters

Current module type is Kotlin/JVM for fast local iteration. It can be moved to an Android library module later without changing plugin descriptor contracts.

Generate registrants:

```sh
zig build run -- plugin sync .
```

`ZiggyRuntime` uses JNA for direct FFI calls. Set `ZIGGY_FFI_LIB` to the shared library path/name when running on desktop JVM.
