# `src/cli/commands/plugin/root/managed_sections.zig`

_Language: Zig_

Managed block rendering and file rewriting for plugin metadata sync.

## Public API

### `updateManagedPluginSections` (fn)

Rewrites managed plugin sections in project files when they exist.

```zig
pub fn updateManagedPluginSections(
    arena: std.mem.Allocator,
    io: std.Io,
    project_root: []const u8,
    records: []const wizig_core.PluginRecord,
) !void {
```

### `renderIosManagedPluginBlock` (fn)

Renders the iOS managed section body with Wizig-specific comment markers.

```zig
pub fn renderIosManagedPluginBlock(
    arena: std.mem.Allocator,
    records: []const wizig_core.PluginRecord,
) ![]u8 {
```

### `renderAndroidManagedPluginBlock` (fn)

Renders the Android managed section body with Wizig-specific comment markers.

```zig
pub fn renderAndroidManagedPluginBlock(
    arena: std.mem.Allocator,
    records: []const wizig_core.PluginRecord,
) ![]u8 {
```

### `renderManagedBlockText` (fn)

Returns `original` with the managed block replaced or appended.

```zig
pub fn renderManagedBlockText(
    arena: std.mem.Allocator,
    original: []const u8,
    begin_marker: []const u8,
    end_marker: []const u8,
    block: []const u8,
) ![]u8 {
```
