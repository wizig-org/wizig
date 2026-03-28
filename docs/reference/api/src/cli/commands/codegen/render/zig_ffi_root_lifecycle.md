# `src/cli/commands/codegen/render/zig_ffi_root_lifecycle.zig`

_Language: Zig_

Runtime lifecycle functions and wire-format read/write helpers
emitted into the generated FFI root module.

Covers: `wizig_runtime_new`, `wizig_runtime_free`, `wizig_runtime_echo`,
`wizig_bytes_free`, error mapping, result unwrapping, and binary wire
format primitives (read/write for u32, i64, bool, string).

## Public API

### `appendLifecycle` (fn)

Appends runtime lifecycle exports, error-mapping utilities, and
binary wire format read/write helpers to the generated FFI root.

```zig
pub fn appendLifecycle(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
```
