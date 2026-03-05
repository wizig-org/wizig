# `cli/src/commands/codegen/render/ios_c_shim.zig`

_Language: Zig_

Renderer for iOS SwiftPM C shim (`Sources/WizigFFI/stub.c`).

The shim exports all `wizig_*` symbols referenced by Swift sources and
forwards calls to the embedded `WizigFFI.framework` at runtime via `dlopen`.

## Public API

### `renderIosSwiftPmShim` (fn)

Renders C wrappers for runtime + generated API symbols.

```zig
pub fn renderIosSwiftPmShim(arena: std.mem.Allocator, spec: api.ApiSpec) ![]u8 {
```
