# Wizig iOS SDK (Stub)

This package will wrap the Wizig FFI (`wizig.h` + `wizigffi`) and expose a Swift-first API.

Planned components:

- `WizigRuntime` Swift type
- generated plugin registrant integration
- SPM-native plugin adapters

Generate registrants:

```sh
zig build run -- plugin sync .
```

To load Zig FFI at runtime during development, set `WIZIG_FFI_LIB` to the built dynamic library path (for example `zig-out/lib/libwizigffi.dylib`).
