# `runtime/core/src/plugins/manifest.zig`

Runtime-packaged plugin manifest parser.

## Public API

### `PluginManifest` (const)

Parsed plugin manifest for app-local runtime usage.

```zig
pub const PluginManifest = struct {
```

### `parse` (fn)

Parses and validates a plugin manifest JSON payload.

```zig
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !PluginManifest {
```

### `deinit` (fn)

Releases all manifest-owned memory.

```zig
    pub fn deinit(self: *PluginManifest, allocator: std.mem.Allocator) void {
```
