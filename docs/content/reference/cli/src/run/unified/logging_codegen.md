# `cli/src/run/unified/logging_codegen.zig`

_Language: Zig_

Unified run logging and codegen preflight helpers.

This module writes per-run metadata logs and ensures code generation is
executed only when source/contract fingerprints change.

## Public API

### `buildLogPath` (fn)

Builds the unified run log path under `<project>/.wizig/logs/run.log`.

```zig
pub fn buildLogPath(arena: std.mem.Allocator, io: std.Io, project_root: []const u8) ![]const u8 {
```

### `appendLogLine` (fn)

Appends a formatted line to the in-memory run log buffer.

```zig
pub fn appendLogLine(
    arena: std.mem.Allocator,
    log_lines: *std.ArrayList(u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
```

### `runCodegenPreflight` (fn)

Executes codegen only when the fingerprint differs from cached state.

```zig
pub fn runCodegenPreflight(
    arena: std.mem.Allocator,
    io: std.Io,
    stderr: *Io.Writer,
    stdout: *Io.Writer,
    project_root: []const u8,
    log_lines: *std.ArrayList(u8),
) !void {
```
