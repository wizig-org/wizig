# `src/ffi/buffer_pool.zig`

_Language: Zig_

Thread-safe tiered buffer pool providing an `std.mem.Allocator` interface.
Wraps `smp_allocator` with tier-based caching to eliminate syscall overhead
and reduce fragmentation for typical FFI output buffer sizes (64 B -- 4 KB).

## Public API

### `BufferPool` (const)

Thread-safe tiered buffer pool. Each tier holds up to `slots_per_tier`
cached buffers; oversized requests fall through to `smp_allocator`.

```zig
pub const BufferPool = struct {
```

### `allocator` (fn)

Returns an `std.mem.Allocator` backed by this pool.

```zig
    pub fn allocator(self: *BufferPool) std.mem.Allocator {
```
