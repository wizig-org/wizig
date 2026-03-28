# `src/cli/commands/codegen/render/zig_ffi_buffer_pool.zig`

_Language: Zig_

Emits the generated FFI output buffer pool implementation.

The generated FFI root keeps this inline so `wizig_bytes_free` can return
buffers without any extra handle parameter while still reusing common sizes.

## Public API

### `appendBufferPool` (fn)

Appends the tiered buffer-pool implementation used by generated FFI roots.

```zig
pub fn appendBufferPool(out: *std.ArrayList(u8), arena: std.mem.Allocator) !void {
```
