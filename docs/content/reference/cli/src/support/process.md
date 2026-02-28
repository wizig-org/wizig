# `cli/src/support/process.zig`

_Language: Zig_

Process execution helpers with checked error reporting.

## Public API

### `CommandResult` (const)

Alias for captured command execution output.

```zig
pub const CommandResult = std.process.RunResult;
```

### `runCapture` (fn)

Runs a subprocess and captures stdout/stderr.

```zig
pub fn runCapture(
    arena: std.mem.Allocator,
    io: std.Io,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !CommandResult {
```

### `runChecked` (fn)

Runs a subprocess and surfaces command output on non-zero exit.

```zig
pub fn runChecked(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    cwd_path: ?[]const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
    description: []const u8,
) !CommandResult {
```

### `commandExists` (fn)

Returns true when `command_name` is discoverable via `which`.

```zig
pub fn commandExists(
    arena: std.mem.Allocator,
    io: std.Io,
    name: []const u8,
) bool {
```
