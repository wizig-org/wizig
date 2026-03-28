# `src/cli/run/unified/options.zig`

_Language: Zig_

Unified run option parsing and root resolution.

## Public API

### `parseUnifiedOptions` (fn)

Parses unified run options or returns `null` for `--help`.

```zig
pub fn parseUnifiedOptions(
    allocator: std.mem.Allocator,
    stderr: *Io.Writer,
    args: []const []const u8,
) !?types.UnifiedOptions {
```

### `printUsage` (fn)

Writes unified run help with the optional project directory default.

```zig
pub fn printUsage(writer: *Io.Writer) !void {
```

### `resolveProjectRoot` (fn)

Resolves a project root to an absolute path.

```zig
pub fn resolveProjectRoot(arena: std.mem.Allocator, io: std.Io, root: []const u8) ![]const u8 {
```
