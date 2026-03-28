# `src/cli/commands/codegen/render/zig_ffi_root_preamble.zig`

_Language: Zig_

Shared preamble emitted before generated FFI method exports.

Emits type definitions, allocator setup, error helpers, and FFI
handshake exports (abi version, contract hash, last-error accessors).

## Public API

### `appendPrelude` (fn)

Appends the FFI prelude: Status/error types, allocator, pointer
cast helpers, and all `wizig_ffi_*` handshake exports.

```zig
pub fn appendPrelude(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
```
