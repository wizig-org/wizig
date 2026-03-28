# `src/cli/run/platform/options.zig`

_Language: Zig_

Public facade for platform run option parsing.

## Public API

### `parseRunOptions` (fn)

Parses CLI arguments into validated platform run options.

```zig
pub fn parseRunOptions(
    allocator: std.mem.Allocator,
    stderr: *std.Io.Writer,
    args: []const []const u8,
) !?types.RunOptions {
```
