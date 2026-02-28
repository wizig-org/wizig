# `cli/src/commands/create/scaffold.zig`

Project scaffolding for `wizig create`.

## Public API

### `CreateError` (const)

Errors emitted by scaffolding helpers.

```zig
pub const CreateError = error{CreateFailed};
```

### `CreatePlatforms` (const)

Platform selection for generated hosts.

```zig
pub const CreatePlatforms = struct {
```

### `createApp` (fn)

Creates a full Wizig application scaffold at `destination_dir_raw`.

```zig
pub fn createApp(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
    platforms: CreatePlatforms,
    explicit_sdk_root: ?[]const u8,
) !void {
```

### `createIos` (fn)

Creates the iOS host scaffold and optionally runs `xcodegen generate`.

```zig
pub fn createIos(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    templates_root: []const u8,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
) !void {
```

### `createAndroid` (fn)

Creates the Android host scaffold and initializes Gradle wrapper files.

```zig
pub fn createAndroid(
    arena: std.mem.Allocator,
    io: std.Io,
    parent_environ_map: *const std.process.Environ.Map,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    app_name_raw: []const u8,
    destination_dir_raw: []const u8,
) !void {
```
