# `core/src/plugins/registry_codegen.zig`

_Language: Zig_

Plugin registry collection and registrant source generation.

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

### `collectFromDir` (fn)

Collects plugin manifests from the given `plugins_dir`.

```zig
pub fn collectFromDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
) !Registry {
```

### `renderLockfile` (fn)

Renders deterministic JSON lockfile text for all plugin records.

```zig
pub fn renderLockfile(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```

### `renderZigRegistrant` (fn)

Renders Zig registrant source from discovered plugins.

```zig
pub fn renderZigRegistrant(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```

### `renderSwiftRegistrant` (fn)

Renders Swift registrant source from discovered plugins.

```zig
pub fn renderSwiftRegistrant(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```

### `renderKotlinRegistrant` (fn)

Renders Kotlin registrant source from discovered plugins.

```zig
pub fn renderKotlinRegistrant(allocator: std.mem.Allocator, records: []const PluginRecord) ![]u8 {
```
