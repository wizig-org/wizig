# `core/src/plugins/manifest.zig`

_Language: Zig_

Plugin manifest v2 schema parsing/validation.

## Public API

### `SpmDependency` (const)

Swift Package Manager dependency descriptor declared by a plugin.

```zig
pub const SpmDependency = struct {
```

### `deinit` (fn)

Releases owned string fields.

```zig
    pub fn deinit(self: *SpmDependency, allocator: std.mem.Allocator) void {
```

### `MavenDependency` (const)

Maven dependency descriptor declared by a plugin.

```zig
pub const MavenDependency = struct {
```

### `deinit` (fn)

Releases owned string fields.

```zig
    pub fn deinit(self: *MavenDependency, allocator: std.mem.Allocator) void {
```

### `PluginManifest` (const)

Parsed plugin manifest with native dependency descriptors.

```zig
pub const PluginManifest = struct {
```

### `parse` (fn)

Parses a JSON plugin manifest payload into a validated structure.

```zig
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !PluginManifest {
```

### `deinit` (fn)

Releases all manifest-owned memory.

```zig
    pub fn deinit(self: *PluginManifest, allocator: std.mem.Allocator) void {
```
