# `cli/src/run/unified/options.zig`

_Language: Zig_

Unified run option parsing and root resolution.

This module keeps argument parsing deterministic and separate from discovery
and delegation logic.

## Public API

### `parseUnifiedOptions` (fn)

Parses unified run options from CLI args.

```zig
pub fn parseUnifiedOptions(args: []const []const u8, stderr: *Io.Writer) !types.UnifiedOptions {
```

### `resolveProjectRoot` (fn)

Resolves project root to an absolute path.

```zig
pub fn resolveProjectRoot(arena: std.mem.Allocator, io: std.Io, root: []const u8) ![]const u8 {
```
