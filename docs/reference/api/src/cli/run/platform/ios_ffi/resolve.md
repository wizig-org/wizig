# `src/cli/run/platform/ios_ffi/resolve.zig`

_Language: Zig_

iOS FFI library path resolution helpers.

The run pipeline uses this lookup when a prebuilt framework or archive is
supplied via environment or when falling back to `zig-out`.

## Public API

### `resolveIosFfiLibraryPath` (fn)

Resolves an existing iOS FFI library path from the environment or `zig-out`.

```zig
pub fn resolveIosFfiLibraryPath(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
) !?[]const u8 {
```
