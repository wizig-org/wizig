# `cli/src/commands/create/scaffold_util.zig`

_Language: Zig_

Shared low-level utilities for scaffold generation.

These functions isolate process execution and filesystem write patterns used
by `wizig create` so orchestration code remains concise.

## Public API

### `joinPath` (fn)

Joins `base` and `name` using the platform path separator.

Special-cases `.` to avoid prefixing the generated path with `./` which
keeps command output and generated metadata stable.

```zig
pub fn joinPath(allocator: std.mem.Allocator, base: []const u8, name: []const u8) ![]u8 {
```

### `writeFileAtomically` (fn)

Writes `contents` to `path` atomically.

The write uses a temporary file and replace operation so partial writes are
never observed by downstream build or codegen steps.

```zig
pub fn writeFileAtomically(io: std.Io, path: []const u8, contents: []const u8) !void {
```

### `runCommand` (fn)

Runs a command and surfaces non-zero exit output through `stderr`.

This helper centralizes command error rendering so scaffold command failures
are consistent and actionable.

```zig
pub fn runCommand(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    cwd_path: []const u8,
    argv: []const []const u8,
    environ_map: ?*const std.process.Environ.Map,
) !void {
```
