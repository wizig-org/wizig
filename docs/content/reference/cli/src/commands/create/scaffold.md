# `cli/src/commands/create/scaffold.zig`

_Language: Zig_

Project scaffolding orchestrator for `wizig create`.

This file coordinates high-level creation flow. Platform-specific host
generation and low-level utilities live in separate modules to keep each
implementation unit focused and below the line-limit policy.

## Public API

### `CreateError` (const)

Errors emitted by scaffolding helpers.

```zig
pub const CreateError = error{CreateFailed};
```

### `CreatePlatforms` (const)

Platform selection for generated hosts.

- `ios`: Generate an iOS host project from templates.
- `android`: Generate an Android host project from templates.
- `macos`: Reserve a placeholder host directory for future desktop support.

```zig
pub const CreatePlatforms = struct {
```

### `createApp` (fn)

Creates a full Wizig application scaffold at `destination_dir_raw`.

The workflow materializes SDK/runtime files, generates selected host
projects, runs initial codegen, and records toolchain lock metadata.

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
    force_host_overwrite: bool,
) !void {
```
