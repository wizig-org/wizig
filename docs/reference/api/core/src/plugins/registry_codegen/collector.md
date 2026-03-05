# `core/src/plugins/registry_codegen/collector.zig`

_Language: Zig_

Plugin manifest discovery, sorting, and validation.

## Public API

### `collectFromDir` (fn)

Collects plugin manifests from the given `plugins_dir`.

```zig
pub fn collectFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
) !Registry {
```
