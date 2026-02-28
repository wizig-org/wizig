# Ziggy iOS SDK (Stub)

This package will wrap the Ziggy FFI (`ziggy.h` + `ziggyffi`) and expose a Swift-first API.

Planned components:

- `ZiggyRuntime` Swift type
- generated plugin registrant integration
- SPM-native plugin adapters

Generate registrants:

```sh
zig build run -- plugin sync .
```

To load Zig FFI at runtime during development, set `ZIGGY_FFI_LIB` to the built dynamic library path (for example `zig-out/lib/libziggyffi.dylib`).
