# `src/cli/commands/codegen/options.zig`

_Language: Zig_

Codegen command-line option parsing.

## Public API

### `default_watch_interval_ms` (const)

Default watch polling interval in milliseconds.

```zig
pub const default_watch_interval_ms: u64 = 500;
```

### `CodegenOptions` (const)

Normalized options for `wizig codegen`.

```zig
pub const CodegenOptions = struct {
```

### `parseCodegenOptions` (fn)

Parses raw CLI arguments into `CodegenOptions`.

```zig
pub fn parseCodegenOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?CodegenOptions {
```

### `printUsage` (fn)

Writes `wizig codegen` usage with the optional project root default.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```
