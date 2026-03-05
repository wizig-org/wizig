# `core/src/plugins/registry_codegen/types.zig`

_Language: Zig_

Shared registry data structures and lifecycle helpers.

## Public API

### `PluginRecord` (const)

Plugin file path paired with parsed manifest contents.

```zig
pub const PluginRecord = struct {
```

### `deinit` (fn)

Releases owned path/manifest data.

```zig
    pub fn deinit(self: *PluginRecord, allocator: std.mem.Allocator) void {
```

### `Registry` (const)

In-memory registry of discovered plugins.

```zig
pub const Registry = struct {
```

### `deinit` (fn)

Releases all registry records and their owned allocations.

```zig
    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
```
